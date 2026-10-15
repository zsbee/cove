import Foundation
import OracleNIO
import Logging

final class OracleBackend: DatabaseBackend, @unchecked Sendable {
    let name = "Oracle"
    let client: OracleSession
    private let runningTask: Task<Void, Never>?

    let syntaxKeywords: Set<String> = [
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE", "SET",
        "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "SCHEMA",
        "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "CROSS", "ON", "AS",
        "AND", "OR", "NOT", "IN", "IS", "NULL", "LIKE", "BETWEEN", "EXISTS",
        "ORDER", "BY", "GROUP", "HAVING", "DISTINCT",
        "UNION", "ALL", "CASE", "WHEN", "THEN", "ELSE", "END", "BEGIN",
        "COMMIT", "ROLLBACK", "VALUES", "DEFAULT", "PRIMARY",
        "KEY", "FOREIGN", "REFERENCES", "CASCADE", "CONSTRAINT", "CHECK",
        "UNIQUE", "ASC", "DESC", "WITH", "RETURNING", "GRANT",
        "REVOKE", "TRUNCATE", "TRIGGER", "FUNCTION", "PROCEDURE",
        "IF", "LOOP", "WHILE", "FOR", "FETCH", "CURSOR", "DECLARE", "EXECUTE",
        "NUMBER", "VARCHAR2", "NVARCHAR2", "CHAR", "NCHAR", "CLOB", "NCLOB",
        "BLOB", "DATE", "TIMESTAMP", "INTERVAL", "RAW", "BOOLEAN",
        "BINARY_FLOAT", "BINARY_DOUBLE", "INTEGER", "FLOAT",
        "TRUE", "FALSE", "COUNT", "SUM", "AVG", "MIN", "MAX",
        "COALESCE", "CAST", "OVER", "PARTITION", "ROW_NUMBER", "RANK",
        "DENSE_RANK", "LAG", "LEAD", "FIRST_VALUE", "LAST_VALUE",
        "SYSDATE", "SYSTIMESTAMP", "ROWNUM", "ROWID", "DUAL",
        "NVL", "NVL2", "DECODE", "TO_DATE", "TO_CHAR", "TO_NUMBER", "TRUNC",
        "MINUS", "CONNECT", "START", "LEVEL", "PRIOR",
        "PIVOT", "UNPIVOT", "MERGE", "USING", "MATCHED",
        "PACKAGE", "BODY", "REPLACE", "FORCE", "PURGE",
        "MATERIALIZED", "SEQUENCE", "SYNONYM", "TYPE",
        "OFFSET", "ROWS", "ONLY", "NEXT",
    ]

    private init(client: OracleSession, runningTask: Task<Void, Never>?) {
        self.client = client
        self.runningTask = runningTask
    }

    static func connect(config: ConnectionConfig) async throws -> OracleBackend {
        if let settings = config.oracle, settings.mode == .tns {
            let jdbc = try OracleJDBCSession(config: config, settings: settings)
            try await withTaskCancellationHandler {
                try await jdbc.ready()
            } onCancel: { jdbc.stop() }
            return OracleBackend(client: OracleSession(native: nil, jdbc: jdbc, decode: { _ in [] }), runningTask: nil)
        }
        let port = Int(config.port) ?? 1521
        let oraConfig = OracleConnection.Configuration(
            host: config.host,
            port: port,
            service: .serviceName(config.database),
            username: config.user,
            password: config.password
        )

        return try await connect(configuration: oraConfig, timeout: 15)
    }

    private static func connect(configuration: OracleConnection.Configuration, timeout: Int) async throws -> OracleBackend {
        // Surface listener/authentication errors instead of the pool's indefinite retries.
        let probe: OracleConnection
        do {
            probe = try await OracleConnection.connect(configuration: configuration, id: 0)
        } catch let error as OracleSQLError {
            if let number = error.serverInfo?.number, [1017, 28000, 28001, 28009].contains(number) {
                throw OracleAuthenticationError(message: error.serverMessage)
            }
            throw DbError.connection(error.serverMessage)
        }
        do {
            try Task.checkCancellation()
            try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await probe.execute(OracleStatement(unsafeSQL: "SELECT 1 FROM DUAL"))
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(timeout))
                        try? await probe.close()
                        throw DbError.connection("Validation query timed out after \(timeout) seconds.")
                    }
                    defer { group.cancelAll() }
                    _ = try await group.next()
                }
            } onCancel: {
                Task { try? await probe.close() }
            }
            try await probe.close()
        } catch {
            try? await probe.close()
            throw error
        }
        let client = OracleClient(configuration: configuration)
        let task = Task { await client.run() }
        return OracleBackend(client: OracleSession(native: client, jdbc: nil, decode: Self.decodeNativeRow), runningTask: task)
    }

    deinit {
        runningTask?.cancel()
    }

    func quoteIdentifier(_ name: String) -> String {
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

extension OracleSQLError {
    var serverMessage: String {
        serverInfo?.message ?? String(describing: self)
    }
}
