import Foundation

enum OracleConnectionMode: String, Codable, CaseIterable, Sendable {
    case basic, tns
}

struct OracleConnectionSettings: Codable, Sendable, Equatable {
    var mode: OracleConnectionMode = .basic
    var tnsAdmin = ""
    var tnsName = ""
    var jdbcURL = ""
    var mutualTLS = false
    var walletPassword = ""

    private enum CodingKeys: String, CodingKey {
        case mode, tnsAdmin, tnsName, jdbcURL, mutualTLS
    }

    var resolvedLocation: (directory: String, alias: String) {
        get throws {
            var directory = tnsAdmin.trimmingCharacters(in: .whitespacesAndNewlines)
            var alias = tnsName.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = jdbcURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty {
                let prefix = "jdbc:oracle:thin:@"
                guard url.hasPrefix(prefix) else {
                    throw OracleConfigurationError("Expected jdbc:oracle:thin:@TNS_NAME?TNS_ADMIN=/path/to/directory. Credentials belong in the User and Password fields.")
                }
                let parts = url.dropFirst(prefix.count).split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
                alias = String(parts[0])
                if parts.count == 2 {
                    for parameter in parts[1].split(separator: "&") {
                        let pair = parameter.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                        guard pair.count == 2, pair[0].uppercased() == "TNS_ADMIN" else {
                            throw OracleConfigurationError("Only the TNS_ADMIN URL parameter is supported.")
                        }
                        directory = String(pair[1]).removingPercentEncoding ?? String(pair[1])
                    }
                }
            }
            guard !alias.isEmpty, alias.allSatisfy({ $0.isLetter || $0.isNumber || "_.-".contains($0) }) else {
                throw OracleConfigurationError("Enter a TNS alias, not a host, service name, or inline connection descriptor.")
            }
            if directory.isEmpty { directory = ProcessInfo.processInfo.environment["TNS_ADMIN"] ?? "" }
            guard !directory.isEmpty else { throw OracleConfigurationError("Choose the TNSADMIN directory containing tnsnames.ora.") }
            return ((directory as NSString).expandingTildeInPath, alias)
        }
    }
}

struct OracleConfigurationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct OracleAuthenticationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct OracleEndpoint: Sendable, Equatable {
    let host: String
    let port: Int
    let service: String
    let usesSID: Bool
    let tls: Bool
    let connectTimeout: Int
    let transportTimeout: Int
    let retryCount: Int
    let retryDelay: Int
    let certificateDN: String?
    let walletDirectory: String?
}

struct OracleConnectionPlan: Sendable {
    let endpoints: [OracleEndpoint]
    let directory: String
}

enum OracleTNS {
    static func connect<Result: Sendable>(plan: OracleConnectionPlan,
                                         attempt: @Sendable (OracleEndpoint) async throws -> Result) async throws -> Result {
        var errors: [String] = []
        for endpoint in plan.endpoints {
            for retry in 0...endpoint.retryCount {
                try Task.checkCancellation()
                do { return try await attempt(endpoint) }
                catch is CancellationError { throw CancellationError() }
                catch let error as OracleAuthenticationError { throw error }
                catch let error as OracleConfigurationError { throw error }
                catch {
                    if retry == endpoint.retryCount {
                        errors.append("\(endpoint.tls ? "TCPS" : "TCP") \(endpoint.host):\(endpoint.port): \(error.localizedDescription)")
                    } else if endpoint.retryDelay > 0 {
                        try await Task.sleep(for: .seconds(endpoint.retryDelay))
                    }
                }
            }
        }
        throw OracleConfigurationError(errors.joined(separator: "\n"))
    }

    static func load(settings: OracleConnectionSettings) throws -> OracleConnectionPlan {
        let location = try settings.resolvedLocation
        let file = URL(fileURLWithPath: location.directory).appendingPathComponent("tnsnames.ora")
        let text: String
        do { text = try String(contentsOf: file, encoding: .utf8) }
        catch { throw OracleConfigurationError("Cannot read tnsnames.ora in \(location.directory): \(error.localizedDescription)") }
        return OracleConnectionPlan(endpoints: try endpoints(in: text, alias: location.alias), directory: location.directory)
    }

    static func aliases(in directory: String) throws -> [String] {
        let file = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath).appendingPathComponent("tnsnames.ora")
        return try parse(String(contentsOf: file, encoding: .utf8)).keys.sorted()
    }

    static func endpoints(in text: String, alias: String) throws -> [OracleEndpoint] {
        let entries = try parse(text)
        guard let root = entries[alias.uppercased()] else { throw OracleConfigurationError("TNS alias '\(alias)' was not found in tnsnames.ora.") }
        try validateRouting(root)
        let descriptions = root.key == "DESCRIPTION" ? [root] : root.children.filter { $0.key == "DESCRIPTION" }
        guard !descriptions.isEmpty else { throw OracleConfigurationError("The TNS alias must contain DESCRIPTION or DESCRIPTION_LIST.") }
        var result: [OracleEndpoint] = []
        for description in descriptions {
            guard let data = description.child("CONNECT_DATA"),
                  let service = data.value("SERVICE_NAME") ?? data.value("SID"), !service.isEmpty else {
                throw OracleConfigurationError("A TNS description is missing SERVICE_NAME or SID.")
            }
            let security = description.child("SECURITY")
            let addresses = description.descendants("ADDRESS")
            guard addresses.count == 1 else {
                throw OracleConfigurationError("Each TNS DESCRIPTION must have one ADDRESS. Use an ordered DESCRIPTION_LIST for multiple endpoints.")
            }
            for address in addresses {
                let proto = address.value("PROTOCOL")?.uppercased() ?? "TCP"
                guard ["TCP", "TCPS"].contains(proto), let host = address.value("HOST"), !host.isEmpty else {
                    throw OracleConfigurationError("Only TCP/TCPS TNS addresses with a HOST are supported.")
                }
                let port = try integer(address, "PORT", default: proto == "TCPS" ? 2484 : 1521, range: 1...65535)
                result.append(OracleEndpoint(
                    host: host, port: port, service: service, usesSID: data.value("SERVICE_NAME") == nil,
                    tls: proto == "TCPS",
                    connectTimeout: try integer(description, "CONNECT_TIMEOUT", default: 15, range: 1...300),
                    transportTimeout: try integer(description, "TRANSPORT_CONNECT_TIMEOUT", default: 10, range: 1...300),
                    retryCount: try integer(description, "RETRY_COUNT", default: 0, range: 0...10),
                    retryDelay: try integer(description, "RETRY_DELAY", default: 0, range: 0...60),
                    certificateDN: security?.value("SSL_SERVER_CERT_DN"),
                    walletDirectory: security?.value("MY_WALLET_DIRECTORY")
                ))
            }
        }
        guard !result.isEmpty else { throw OracleConfigurationError("No TCP/TCPS addresses found in the TNS alias.") }
        return result
    }

    private static func integer(_ node: Node, _ key: String, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let text = node.value(key) else { return fallback }
        guard let value = Int(text), range.contains(value) else { throw OracleConfigurationError("\(key) must be an integer in \(range).") }
        return value
    }

    private static func validateRouting(_ node: Node) throws {
        if ["DESCRIPTION_LIST", "ADDRESS_LIST", "DESCRIPTION"].contains(node.key) {
            if let loadBalance = node.value("LOAD_BALANCE"), !["OFF", "NO", "FALSE"].contains(loadBalance.uppercased()) {
                throw OracleConfigurationError("TNS LOAD_BALANCE is not supported; use LOAD_BALANCE=OFF.")
            }
            if let failover = node.value("FAILOVER"), !["ON", "YES", "TRUE"].contains(failover.uppercased()) {
                throw OracleConfigurationError("TNS FAILOVER=OFF is not supported for ordered endpoint selection.")
            }
            if let route = node.value("SOURCE_ROUTE"), !["OFF", "NO", "FALSE"].contains(route.uppercased()) {
                throw OracleConfigurationError("TNS SOURCE_ROUTE is not supported.")
            }
        }
        for child in node.children { try validateRouting(child) }
    }

    private struct Node {
        let key: String
        let scalar: String?
        let children: [Node]
        func child(_ key: String) -> Node? { children.first { $0.key == key } }
        func value(_ key: String) -> String? { child(key)?.scalar }
        func descendants(_ key: String) -> [Node] {
            children.flatMap { $0.key == key ? [$0] : $0.descendants(key) }
        }
    }

    private static func parse(_ text: String) throws -> [String: Node] {
        var parser = Parser(characters: Array(text))
        var entries: [String: Node] = [:]
        while parser.skipSpace() {
            var aliases: [String] = []
            repeat {
                aliases.append(try parser.token(until: [",", "="]).uppercased())
                if parser.peek == "," { parser.index += 1 } else { break }
            } while true
            try parser.consume("=")
            let node = try parser.node(depth: 0)
            for alias in aliases { entries[alias] = node }
        }
        return entries
    }

    private struct Parser {
        let characters: [Character]
        var index = 0
        var peek: Character? { index < characters.count ? characters[index] : nil }

        @discardableResult mutating func skipSpace() -> Bool {
            while let c = peek {
                if c.isWhitespace { index += 1 }
                else if c == "#" { while let c = peek, c != "\n" { index += 1 } }
                else { return true }
            }
            return false
        }

        mutating func consume(_ expected: Character) throws {
            skipSpace()
            guard peek == expected else { throw OracleConfigurationError("Malformed tnsnames.ora: expected '\(expected)' near character \(index).") }
            index += 1
        }

        mutating func token(until delimiters: Set<Character>) throws -> String {
            skipSpace()
            var value = ""
            var quote: Character?
            while let c = peek {
                if let activeQuote = quote {
                    index += 1
                    if c == activeQuote { quote = nil } else { value.append(c) }
                } else if c == "\"" || c == "'" { quote = c; index += 1 }
                else if delimiters.contains(c) || c == "#" { break }
                else { value.append(c); index += 1 }
            }
            guard quote == nil else { throw OracleConfigurationError("Unterminated quoted value in tnsnames.ora.") }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw OracleConfigurationError("Empty value in tnsnames.ora near character \(index).") }
            return trimmed
        }

        mutating func node(depth: Int) throws -> Node {
            guard depth < 32 else { throw OracleConfigurationError("TNS descriptor nesting exceeds 32 levels.") }
            try consume("(")
            let key = try token(until: ["=", "(", ")"]).uppercased()
            try consume("=")
            skipSpace()
            var children: [Node] = []
            var scalar: String?
            if peek == "(" {
                while peek == "(" { children.append(try node(depth: depth + 1)); skipSpace() }
            } else { scalar = try token(until: [")"]) }
            try consume(")")
            return Node(key: key, scalar: scalar, children: children)
        }
    }
}
