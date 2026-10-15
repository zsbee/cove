import Foundation
import OracleNIO

struct OracleResultRow: Sendable {
    let values: [String?]
    let columns: [ColumnInfo]
}

struct OracleResultRows: AsyncSequence, Sendable {
    typealias Element = OracleResultRow
    let rows: [OracleResultRow]
    let columns: [ColumnInfo]
    let affected: Int?
    func makeAsyncIterator() -> AsyncStream<Element>.Iterator { stream(rows).makeAsyncIterator() }
    private func stream<T: Sendable>(_ values: [T]) -> AsyncStream<T> {
        AsyncStream { continuation in
            for value in values { continuation.yield(value) }
            continuation.finish()
        }
    }
    func decode(_ type: String.Type) -> AsyncStream<String> { stream(rows.map { $0.values.first.flatMap { $0 } ?? "" }) }
    func decode(_ type: Int.Type) -> AsyncStream<Int> { stream(rows.map { Int($0.values.first.flatMap { $0 } ?? "0") ?? 0 }) }
    func decode(_ type: (String, String).Type) -> AsyncStream<(String, String)> { stream(rows.map { ($0.values[0] ?? "", $0.values[1] ?? "") }) }
    func decode(_ type: (String, String, Int).Type) -> AsyncStream<(String, String, Int)> { stream(rows.map { ($0.values[0] ?? "", $0.values[1] ?? "", Int($0.values[2] ?? "0") ?? 0) }) }
    func decode(_ type: (String, String, String, String).Type) -> AsyncStream<(String, String, String, String)> { stream(rows.map { ($0.values[0] ?? "", $0.values[1] ?? "", $0.values[2] ?? "", $0.values[3] ?? "") }) }
}

struct OracleSession: Sendable {
    let native: OracleClient?
    let jdbc: OracleJDBCSession?
    let decode: @Sendable (OracleRow) -> [String?]

    func withConnection<T>(_ operation: (inout OracleSession) async throws -> T) async throws -> T {
        var session = self
        return try await operation(&session)
    }

    func execute(_ sql: String) async throws -> OracleResultRows {
        if let jdbc {
            return try await withTaskCancellationHandler {
                try await jdbc.execute(sql)
            } onCancel: { jdbc.stop() }
        }
        guard let native else { throw DbError.connection("Oracle session is closed") }
        return try await native.withConnection { connection in
            let stream = try await connection.execute(OracleStatement(unsafeSQL: sql))
            var rows: [OracleResultRow] = []
            var columns: [ColumnInfo] = []
            for try await row in stream {
                if columns.isEmpty {
                    columns = row.map { ColumnInfo(name: $0.columnName, typeName: String(describing: $0.dataType), isPrimaryKey: false) }
                }
                rows.append(OracleResultRow(values: decode(row), columns: columns))
            }
            return OracleResultRows(rows: rows, columns: columns, affected: rows.isEmpty ? 0 : nil)
        }
    }
}

actor OracleJDBCSession {
    nonisolated private let process: Process
    private let input: FileHandle
    private let output: FileHandle

    private struct Response: Decodable {
        struct Column: Decodable { let name: String; let type: String }
        var columns: [Column]?
        var rows: [[String?]]?
        var affected: Int?
        var error: String?
    }

    init(config: ConnectionConfig, settings: OracleConnectionSettings) throws {
        let resources = Bundle.main.resourceURL?.appendingPathComponent("OracleJDBC")
        guard let resources, FileManager.default.fileExists(atPath: resources.appendingPathComponent("CoveOracleBridge.class").path) else {
            throw DbError.connection("Oracle JDBC helper is missing. Rebuild using build-and-run.py.")
        }
        let location = try settings.resolvedLocation
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/java")
        process.arguments = ["-cp", resources.path + ":" + resources.path + "/*", "CoveOracleBridge"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        try Self.write("jdbc:oracle:thin:@\(location.alias)?TNS_ADMIN=\(location.directory)", to: input)
        try Self.write(config.user, to: input)
        try Self.write(config.password, to: input)
    }

    deinit {
        try? input.close()
        try? output.close()
        if process.isRunning { process.terminate() }
    }

    func ready() throws { _ = try response() }

    nonisolated func stop() {
        if process.isRunning { process.terminate() }
    }

    func execute(_ sql: String) throws -> OracleResultRows {
        try Self.write(sql, to: input)
        let result = try response()
        let columns = (result.columns ?? []).map { ColumnInfo(name: $0.name, typeName: $0.type, isPrimaryKey: false) }
        return OracleResultRows(rows: (result.rows ?? []).map { OracleResultRow(values: $0, columns: columns) }, columns: columns, affected: result.affected)
    }

    private static func write(_ string: String, to handle: FileHandle) throws {
        let bytes = Data(string.utf8)
        var length = UInt32(bytes.count).bigEndian
        try handle.write(contentsOf: withUnsafeBytes(of: &length) { Data($0) } + bytes)
    }

    private func read(_ count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let part = try output.read(upToCount: count - data.count), !part.isEmpty else {
                throw DbError.connection("Oracle JDBC helper exited. Verify Java 17+ is installed.")
            }
            data.append(part)
        }
        return data
    }

    private func response() throws -> Response {
        let header = try read(4)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length <= 256 * 1024 * 1024 else { throw DbError.other("Oracle result exceeds 256 MB") }
        let result = try JSONDecoder().decode(Response.self, from: read(Int(length)))
        if let error = result.error { throw DbError.connection(error) }
        return result
    }
}
