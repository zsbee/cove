import Foundation

@main
struct OracleChecks {
    actor Attempts {
        var hosts: [String] = []
        func record(_ host: String) { hosts.append(host) }
    }

    static func main() async throws {
        let text = """
        # Multiple aliases and nested failover descriptions
        demo, synonym=(DESCRIPTION_LIST=(LOAD_BALANCE=OFF)(FAILOVER=ON)
          (DESCRIPTION=(RETRY_COUNT=1)(ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)(HOST=first.example)(PORT=1521)))
            (CONNECT_DATA=(SERVICE_NAME=first_service)))
          (DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=second.example)(PORT=2484))
            (CONNECT_DATA=(SERVICE_NAME=second_service))
            (SECURITY=(SSL_SERVER_CERT_DN="CN=second.example"))))
        """
        let endpoints = try OracleTNS.endpoints(in: text, alias: "DeMo")
        precondition(endpoints.map(\.host) == ["first.example", "second.example"])
        precondition(endpoints.map(\.tls) == [false, true])
        precondition(endpoints.map(\.service) == ["first_service", "second_service"])
        precondition(endpoints[1].certificateDN == "CN=second.example")
        let synonym = try OracleTNS.endpoints(in: text, alias: "synonym")
        precondition(synonym == endpoints)

        var settings = OracleConnectionSettings()
        settings.mode = .tns
        settings.tnsName = "ignored"
        settings.tnsAdmin = "/ignored"
        settings.jdbcURL = "jdbc:oracle:thin:@demo?TNS_ADMIN=/tmp/my%20wallet"
        settings.walletPassword = "test-only-secret"
        let location = try settings.resolvedLocation
        precondition(location.alias == "demo" && location.directory == "/tmp/my wallet")
        let json = try JSONEncoder().encode(settings)
        precondition(!String(decoding: json, as: UTF8.self).contains("test-only-secret"))
        let restored = try JSONDecoder().decode(OracleConnectionSettings.self, from: json)
        precondition(restored.walletPassword.isEmpty && restored.jdbcURL == settings.jdbcURL)

        func rejects(_ operation: () throws -> Void) {
            do { try operation(); fatalError("Expected validation failure") } catch {}
        }
        rejects { _ = try OracleTNS.endpoints(in: text, alias: "missing") }
        rejects { _ = try OracleTNS.endpoints(in: "demo=(DESCRIPTION=", alias: "demo") }
        rejects { _ = try OracleTNS.endpoints(in: text.replacingOccurrences(of: "LOAD_BALANCE=OFF", with: "LOAD_BALANCE=ON"), alias: "demo") }
        rejects { _ = try OracleTNS.endpoints(in: text.replacingOccurrences(of: "PORT=1521", with: "PORT=0"), alias: "demo") }
        settings.jdbcURL = "jdbc:oracle:thin:user/password@demo"
        rejects { _ = try settings.resolvedLocation }

        let attempts = Attempts()
        let plan = OracleConnectionPlan(endpoints: endpoints, directory: "/tmp")
        let connectedHost = try await OracleTNS.connect(plan: plan) { endpoint in
            await attempts.record(endpoint.host)
            if !endpoint.tls { throw URLError(.cannotConnectToHost) }
            return endpoint.host
        }
        let hosts = await attempts.hosts
        precondition(connectedHost == "second.example")
        precondition(hosts == ["first.example", "first.example", "second.example"])
        do {
            let _: String = try await OracleTNS.connect(plan: plan) { _ in throw CancellationError() }
            fatalError("Expected cancellation")
        } catch is CancellationError {}
        print("Oracle checks passed: JDBC override, TNS parsing, validation, secret exclusion, retries, failover, cancellation.")

        if CommandLine.arguments.count == 3 {
            settings.jdbcURL = ""
            settings.tnsAdmin = CommandLine.arguments[1]
            settings.tnsName = CommandLine.arguments[2]
            let local = try OracleTNS.load(settings: settings)
            print("Local TNS alias validated: \(local.endpoints.count) endpoints, protocols \(local.endpoints.map { $0.tls ? "TCPS" : "TCP" }.joined(separator: " → ")).")
        }
    }
}
