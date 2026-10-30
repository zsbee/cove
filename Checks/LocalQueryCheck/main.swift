import Foundation
import Darwin

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw CheckFailure(description: message) }
}

func expectFailure(_ message: String, _ operation: () throws -> Void) throws {
    do { try operation() }
    catch is QueryAgentError { return }
    throw CheckFailure(description: message)
}

let fixture = QueryDatabaseSchema(
    schema: CompletionSchema(schemas: ["APP"], tables: ["APP": [
        CompletionTable(name: "CUSTOMERS", columns: [
            CompletionColumn(name: "ID", typeName: "NUMBER"),
            CompletionColumn(name: "NAME", typeName: "VARCHAR2(100)"),
        ]),
        CompletionTable(name: "ORDERS", columns: [
            CompletionColumn(name: "ID", typeName: "NUMBER"),
            CompletionColumn(name: "CUSTOMER_ID", typeName: "NUMBER"),
            CompletionColumn(name: "TOTAL", typeName: "NUMBER(12,2)"),
            CompletionColumn(name: "ORDER_DATE", typeName: "DATE"),
        ]),
        CompletionTable(name: "UNRELATED", columns: [CompletionColumn(name: "SECRET", typeName: "VARCHAR2(20)")]),
    ]], functions: [], types: []),
    keys: [
        QuerySchemaKey(schema: "APP", table: "CUSTOMERS", name: "CUSTOMER_PK", columns: ["ID"], referencedSchema: nil, referencedTable: nil, referencedColumns: []),
        QuerySchemaKey(schema: "APP", table: "ORDERS", name: "ORDER_PK", columns: ["ID"], referencedSchema: nil, referencedTable: nil, referencedColumns: []),
        QuerySchemaKey(schema: "APP", table: "ORDERS", name: "CUSTOMER_FK", columns: ["CUSTOMER_ID"], referencedSchema: "APP", referencedTable: "CUSTOMERS", referencedColumns: ["ID"]),
    ],
    dialectNotes: "Oracle SQL. DUAL is an available Oracle built-in table."
)

func context(_ instruction: String, schema: QueryDatabaseSchema = fixture, selectedPath: [String]? = nil) throws -> String {
    try LocalQueryContextBuilder.build(schema: schema, backendName: "Oracle", database: "APP", serverVersion: "19c",
                                       selectedPath: selectedPath, instruction: instruction, currentQuery: "")
}

func chatData(sql: String, error: String = "", reason: String = "stop", done: Bool = true) throws -> Data {
    let output = try JSONSerialization.data(withJSONObject: ["sql": sql, "unavailableReason": error])
    return try JSONSerialization.data(withJSONObject: [
        "message": ["role": "assistant", "content": String(decoding: output, as: UTF8.self)],
        "done": done, "done_reason": reason,
    ])
}

final class MockOllamaProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        do {
            var data: Data
            var status = 200
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                var collected = Data()
                while stream.hasBytesAvailable {
                    let size = stream.read(&buffer, maxLength: buffer.count)
                    if size <= 0 { break }
                    collected.append(contentsOf: buffer.prefix(size))
                }
                body = collected
            }
            let json = try body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            let model = json["model"] as? String ?? "fixture"
            switch request.url?.path {
            case "/api/tags":
                data = Data(#"{"models":[{"name":"fixture"},{"name":"remote:cloud"}]}"#.utf8)
            case "/api/show":
                if model == "remote" {
                    data = Data(#"{"remote_model":"other","remote_host":"https://example.com"}"#.utf8)
                } else if model == "missing" {
                    status = 404
                    data = Data()
                } else if model == "cancelled" {
                    throw URLError(.cancelled)
                } else if model == "timeout" {
                    throw URLError(.timedOut)
                } else if model == "server-error" {
                    status = 500
                    data = Data()
                } else if model == "malformed" {
                    data = Data("not json".utf8)
                } else {
                    data = Data("{}".utf8)
                }
            case "/api/chat":
                try check(json["stream"] as? Bool == false, "Requests must not stream partial SQL")
                try check(json["tools"] == nil, "Local model must not receive tools")
                try check((json["format"] as? [String: Any])?["type"] as? String == "object", "Structured output schema missing")
                let encoded = String(decoding: body ?? Data(), as: UTF8.self)
                guard let sqlProperty = encoded.range(of: "\"sql\":{\"type\":\"string\"}"),
                      let reasonProperty = encoded.range(of: "\"unavailableReason\":{\"type\":\"string\"}") else {
                    throw CheckFailure(description: "Output properties missing")
                }
                try check(sqlProperty.lowerBound < reasonProperty.lowerBound, "SQL must precede the refusal field in the schema grammar")
                data = try chatData(sql: "SELECT ID FROM APP.CUSTOMERS")
            default:
                throw CheckFailure(description: "Unexpected Ollama route")
            }
            guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else {
                throw CheckFailure(description: "Bad mock URL")
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
}

@main
struct LocalQueryChecks {
    static func main() async {
        do { try await run() }
        catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }

    static func run() async throws {
        if CommandLine.arguments.contains("--context") {
            print(try context("List the 10 largest ORDERS by TOTAL."))
            return
        }
        for endpoint in ["http://127.0.0.1:11434", "http://localhost:11434/", "http://[::1]:11434"] {
            _ = try LocalQuerySettings(endpoint: endpoint).baseURL()
        }
        for endpoint in ["https://example.com", "http://192.168.1.1:11434", "http://localhost.evil.test", "http://localhost@evil.test", "http://localhost/api", "http://localhost?redirect=1", "file:///tmp/model", "http://user:password@localhost"] {
            try expectFailure("Remote or malformed endpoint accepted: \(endpoint)") { _ = try LocalQuerySettings(endpoint: endpoint).baseURL() }
        }
        let suite = "CoveLocalAI-check-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw CheckFailure(description: "No isolated preference suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        try check(LocalQuerySettings.load(from: defaults).model == LocalQuerySettings.defaultModel, "Default model missing")
        try check(LocalQuerySettings.load(from: defaults).autoStart, "Automatic startup should default to enabled")
        defaults.set(false, forKey: LocalQuerySettings.autoStartKey)
        try check(!LocalQuerySettings.load(from: defaults).autoStart, "Automatic startup opt-out was ignored")
        defaults.set("fixture", forKey: LocalQuerySettings.modelKey)
        try check(LocalQuerySettings.load(from: defaults).model == "fixture", "Isolated model preference not loaded")

        let generated = try OllamaQueryClient.decodeGeneration(chatData(sql: " SELECT ID FROM APP.CUSTOMERS "))
        try check(generated.query == "SELECT ID FROM APP.CUSTOMERS", "SQL whitespace not trimmed")
        for data in [try chatData(sql: ""), try chatData(sql: "SELECT 1", error: "Choose a table"),
                     try chatData(sql: "SELECT 1", reason: "length"), try chatData(sql: "SELECT 1", done: false),
                     try chatData(sql: "```sql\nSELECT 1\n```"), Data("not json".utf8)] {
            try expectFailure("Invalid or incomplete output accepted") { _ = try OllamaQueryClient.decodeGeneration(data) }
        }

        let focused = try context("Show ORDERS")
        try check(focused.contains("\"APP\".\"ORDERS\""), "Requested table missing")
        try check(focused.contains("REFERENCES \"APP\".\"CUSTOMERS\" (\"ID\")"), "Join relationship missing")
        try check(!focused.contains("SECRET"), "Unrelated columns leaked into focused context")
        try check(!focused.contains("Host:") && !focused.contains("password"), "Connection metadata present")
        let selected = try context("show all rows", selectedPath: ["APP", "Tables", "UNRELATED"])
        try check(selected.contains("SECRET") && !selected.contains("CUSTOMER_ID"), "Browser selection not respected")
        let columns = (0..<200).map { CompletionColumn(name: "COLUMN_\($0)", typeName: "VARCHAR2(100)") }
        let large = QueryDatabaseSchema(schema: CompletionSchema(schemas: ["APP"], tables: ["APP":
            (0..<100).map { CompletionTable(name: "TABLE_\($0)", columns: columns) }
        ], functions: [], types: []))
        let bounded = try context("show rows", schema: large)
        try check(bounded.count <= LocalQueryContextBuilder.characterBudget, "Context budget exceeded")
        try check(bounded.contains("omitted"), "Omitted metadata not disclosed")
        let composite = QueryDatabaseSchema(schema: fixture.schema, keys: [
            QuerySchemaKey(schema: "APP", table: "ORDERS", name: "COMPOSITE", columns: ["ID", "CUSTOMER_ID"], referencedSchema: "APP", referencedTable: "CUSTOMERS", referencedColumns: ["ID", "NAME"]),
        ])
        let compositeContext = try context("ORDERS", schema: composite)
        try check(compositeContext.contains("(\"ID\", \"CUSTOMER_ID\") REFERENCES \"APP\".\"CUSTOMERS\" (\"ID\", \"NAME\")"), "Composite key order lost")
        try expectFailure("Empty schema accepted") { _ = try context("show rows", schema: QueryDatabaseSchema(schema: .empty)) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockOllamaProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = OllamaQueryClient(settings: LocalQuerySettings(model: "fixture"), session: session)
        let models = try await client.testConnection()
        try check(models == ["fixture"], "Cloud models not filtered")
        let response = try await client.generate(request: QueryAgentRequest(instruction: "show customers", currentQuery: "", databaseContext: focused))
        try check(response.query == "SELECT ID FROM APP.CUSTOMERS", "HTTP generation failed")
        for model in ["remote", "remote:cloud", "missing", "", "timeout", "server-error", "malformed"] {
            do {
                _ = try await OllamaQueryClient(settings: LocalQuerySettings(model: model), session: session)
                    .generate(request: QueryAgentRequest(instruction: "test", currentQuery: "", databaseContext: focused))
                throw CheckFailure(description: "Remote/missing model was accepted: \(model)")
            } catch is QueryAgentError {}
        }
        do {
            _ = try await OllamaQueryClient(settings: LocalQuerySettings(model: "cancelled"), session: session)
                .generate(request: QueryAgentRequest(instruction: "test", currentQuery: "", databaseContext: focused))
            throw CheckFailure(description: "Cancellation was swallowed")
        } catch is CancellationError {}
        print("PASS: local endpoint restrictions, isolated preferences, structured responses, schema scope/budget, composite keys, HTTP generation, cloud rejection, missing models, cancellation")

        if CommandLine.arguments.contains("--startup") {
            try await checkServerStartup()
        }

        if CommandLine.arguments.contains("--live") {
            let client = OllamaQueryClient(settings: LocalQuerySettings())
            _ = try await client.testConnection()
            for instruction in [
                "List the 10 largest ORDERS by TOTAL.",
                "Join CUSTOMERS and ORDERS. Show each customer's NAME and sum of TOTAL, ordered highest first.",
                "List ORDERS placed this calendar month using Oracle date functions.",
                "Use a CTE and ROW_NUMBER to show each customer's largest order from ORDERS.",
                "List CUSTOMERS that have no ORDERS using NOT EXISTS.",
            ] {
                let start = Date()
                print("\nPROMPT: \(instruction)")
                let result = try await client.generate(request: QueryAgentRequest(instruction: instruction, currentQuery: "", databaseContext: try context(instruction)))
                print("\(result.query)\nTime: \(Int(Date().timeIntervalSince(start)))s")
                try check(!result.query.uppercased().contains(" LIMIT "), "Model emitted non-Oracle LIMIT")
            }
            do {
                _ = try await client.generate(request: QueryAgentRequest(instruction: "List invoices from the INVOICES table.", currentQuery: "", databaseContext: try context("ORDERS")))
                throw CheckFailure(description: "Model invented a missing table instead of requesting context")
            } catch let error as QueryAgentError {
                print("\nPASS: missing-table request returned an error: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    static func checkServerStartup() async throws {
        guard let executable = ExecutableResolver.resolve("ollama") else {
            throw CheckFailure(description: "Install Ollama before running --startup")
        }
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw CheckFailure(description: "Cannot reserve test port") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        var size = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socket, $0, &size) }
        }
        Darwin.close(socket)
        try check(bound == 0 && named == 0, "Cannot obtain test port")
        let port = UInt16(bigEndian: address.sin_port)
        let settings = LocalQuerySettings(endpoint: "http://127.0.0.1:\(port)", timeout: 1)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/ollama-startup-check-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let wrapper = directory.appendingPathComponent("ollama-check")
        let escapedExecutable = executable.replacingOccurrences(of: "'", with: "'\\''")
        try "#!/bin/sh\necho $$ >> \"$0.launches\"\nexec '\(escapedExecutable)' \"$@\"\n".write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)

        let missing = OllamaServer(executable: { nil })
        var disabled = settings
        disabled.autoStart = false
        try await missing.ensureRunning(settings: disabled)
        do {
            try await missing.ensureRunning(settings: settings)
            throw CheckFailure(description: "Missing executable was not reported")
        } catch is QueryAgentError {}

        let owner = OllamaServer(executable: { wrapper.path })
        defer { owner.stopOwnedServers() }
        async let first: Void = owner.ensureRunning(settings: settings)
        async let second: Void = owner.ensureRunning(settings: settings)
        _ = try await (first, second)
        let client = OllamaQueryClient(settings: settings)
        _ = try await client.installedModels()
        let marker = wrapper.appendingPathExtension("launches")
        let launches = try String(contentsOf: marker, encoding: .utf8).split(separator: "\n")
        try check(launches.count == 1, "Concurrent startup launched more than one process")

        let borrower = OllamaServer(executable: { nil })
        try await borrower.ensureRunning(settings: settings)
        borrower.stopOwnedServers()
        _ = try await client.installedModels()
        print("PASS: automatic startup, concurrent startup deduplication, and reuse without stopping an existing server")

        owner.stopOwnedServers()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline, (try? await client.installedModels()) != nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        let stillRunning = (try? await client.installedModels()) != nil
        try check(!stillRunning, "Owned Ollama did not stop")

        let broken = directory.appendingPathComponent("broken-ollama")
        try "#!/bin/sh\nexit 7\n".write(to: broken, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: broken.path)
        let failure = OllamaServer(executable: { broken.path })
        defer { failure.stopOwnedServers() }
        do {
            try await failure.ensureRunning(settings: settings)
            throw CheckFailure(description: "Failed child process was not reported")
        } catch is QueryAgentError {}

        try await owner.ensureRunning(settings: settings)
        _ = try await client.installedModels()
        print("PASS: automatic startup opt-out, missing executable, failed process, owned-server shutdown, and restart")
    }
}
