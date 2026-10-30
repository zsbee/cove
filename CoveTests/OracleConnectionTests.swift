import XCTest
@testable import Cove

final class OracleConnectionTests: XCTestCase {
    private let descriptor = """
    # Ordered TCP then TLS, like an IntelliJ TNS connection
    demo, other = (DESCRIPTION_LIST=(LOAD_BALANCE=OFF)(FAILOVER=ON)
      (DESCRIPTION=(CONNECT_TIMEOUT=15)(TRANSPORT_CONNECT_TIMEOUT=3)(RETRY_COUNT=3)(RETRY_DELAY=2)
        (ADDRESS_LIST=(FAILOVER=on)(ADDRESS=(PROTOCOL=tcp)(HOST=internal.example)(PORT=1521)))
        (CONNECT_DATA=(SERVICE_NAME=internal_service)))
      (DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=cloud.example)(PORT=2484))
        (CONNECT_DATA=(SERVICE_NAME=cloud_service))
        (SECURITY=(SSL_SERVER_CERT_DN="CN=cloud.example"))))
    """

    func testOrderedNestedDescriptorsAndAliasNames() throws {
        let endpoints = try OracleTNS.endpoints(in: descriptor, alias: "DeMo")
        XCTAssertEqual(endpoints.map(\.host), ["internal.example", "cloud.example"])
        XCTAssertEqual(endpoints.map(\.service), ["internal_service", "cloud_service"])
        XCTAssertEqual(endpoints.map(\.tls), [false, true])
        XCTAssertEqual(endpoints[0].retryCount, 3)
        XCTAssertEqual(endpoints[0].transportTimeout, 3)
        XCTAssertEqual(endpoints[1].certificateDN, "CN=cloud.example")
        XCTAssertEqual(try OracleTNS.endpoints(in: descriptor, alias: "other"), endpoints)
    }

    func testURLOverridesFieldsAndDecodesDirectory() throws {
        var settings = OracleConnectionSettings()
        settings.tnsName = "ignored"
        settings.tnsAdmin = "/ignored"
        settings.jdbcURL = "jdbc:oracle:thin:@demo?TNS_ADMIN=/tmp/my%20wallet"
        let location = try settings.resolvedLocation
        XCTAssertEqual(location.alias, "demo")
        XCTAssertEqual(location.directory, "/tmp/my wallet")
    }

    func testURLWithoutDirectoryUsesFormDirectory() throws {
        var settings = OracleConnectionSettings()
        settings.tnsAdmin = "/tmp/wallet"
        settings.jdbcURL = "jdbc:oracle:thin:@demo"
        XCTAssertEqual(try settings.resolvedLocation.directory, "/tmp/wallet")
    }

    func testRejectsMissingAliasMalformedDescriptorsAndUnsupportedRouting() {
        XCTAssertThrowsError(try OracleTNS.endpoints(in: descriptor, alias: "missing"))
        XCTAssertThrowsError(try OracleTNS.endpoints(in: "demo=(DESCRIPTION=", alias: "demo"))
        XCTAssertThrowsError(try OracleTNS.endpoints(in: descriptor.replacingOccurrences(of: "LOAD_BALANCE=OFF", with: "LOAD_BALANCE=ON"), alias: "demo"))
        XCTAssertThrowsError(try OracleTNS.endpoints(in: descriptor.replacingOccurrences(of: "PORT=1521", with: "PORT=0"), alias: "demo"))
    }

    func testRejectsCredentialBearingAndUnsupportedURLs() {
        var settings = OracleConnectionSettings()
        settings.jdbcURL = "jdbc:oracle:thin:user/password@demo"
        XCTAssertThrowsError(try settings.resolvedLocation)
        settings.jdbcURL = "jdbc:oracle:thin:@demo?password=secret"
        XCTAssertThrowsError(try settings.resolvedLocation)
    }

    func testConnectionPanelAllowsJDBCRoutingWithoutNativeRestrictions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cove-jdbc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("tnsnames.ora")
        var settings = OracleConnectionSettings()
        settings.mode = .tns
        settings.tnsName = "demo"
        settings.tnsAdmin = directory.path

        for text in [
            descriptor.replacingOccurrences(of: "LOAD_BALANCE=OFF", with: "LOAD_BALANCE=ON"),
            """
            demo=(DESCRIPTION=(LOAD_BALANCE=ON)
              (ADDRESS_LIST=(LOAD_BALANCE=ON)(FAILOVER=OFF)
                (ADDRESS=(PROTOCOL=TCP)(HOST=first.example)(PORT=1521))
                (ADDRESS=(PROTOCOL=TCPS)(HOST=second.example)(PORT=2484)))
              (CONNECT_DATA=(SERVICE_NAME=demo_service)))
            """,
            descriptor.replacingOccurrences(of: "FAILOVER=ON", with: "FAILOVER=OFF"),
        ] {
            try text.write(to: file, atomically: true, encoding: .utf8)
            XCTAssertNoThrow(try BackendType.oracle.validateConnectionSettings(settings))
        }

        settings.jdbcURL = "jdbc:oracle:thin:@other?TNS_ADMIN=\(directory.path)"
        settings.tnsName = "ignored"
        settings.tnsAdmin = "/ignored"
        XCTAssertNoThrow(try BackendType.oracle.validateConnectionSettings(settings))
        settings.jdbcURL = ""
        settings.tnsAdmin = directory.path
        settings.tnsName = "missing"
        XCTAssertThrowsError(try BackendType.oracle.validateConnectionSettings(settings))
        settings.tnsName = "demo"
        try "demo=(DESCRIPTION=".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try BackendType.oracle.validateConnectionSettings(settings))
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try BackendType.oracle.validateConnectionSettings(settings))
        settings.jdbcURL = "jdbc:oracle:thin:user/password@demo"
        XCTAssertThrowsError(try BackendType.oracle.validateConnectionSettings(settings))
        settings.jdbcURL = "jdbc:oracle:thin:@demo?password=secret"
        XCTAssertThrowsError(try BackendType.oracle.validateConnectionSettings(settings))
    }

    func testSavedSettingsRoundTripWithoutPasswordsAndOldConnectionsDecode() throws {
        var settings = OracleConnectionSettings()
        settings.mode = .tns
        settings.tnsName = "demo"
        settings.tnsAdmin = "/tmp/wallet"
        settings.walletPassword = "wallet-secret"
        let connection = SavedConnection(name: "Demo", backend: .oracle, host: "", port: "1521", user: "demo", password: "database-secret", database: "", oracle: settings)
        let data = try JSONEncoder().encode(connection)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("wallet-secret"))
        XCTAssertFalse(text.contains("database-secret"))
        let decoded = try JSONDecoder().decode(SavedConnection.self, from: data)
        XCTAssertEqual(decoded.oracle?.tnsName, "demo")
        XCTAssertEqual(decoded.oracle?.walletPassword, "")
        let old = SavedConnection(name: "Old", backend: .oracle, host: "localhost", port: "1521", user: "demo", database: "service")
        XCTAssertNil(try JSONDecoder().decode(SavedConnection.self, from: JSONEncoder().encode(old)).oracle)
    }
}
