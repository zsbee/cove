import XCTest
@testable import Cove

final class LocalQueryTests: XCTestCase {
    func testOnlyLoopbackEndpointsAreAccepted() throws {
        for endpoint in ["http://127.0.0.1:11434", "http://localhost:11434", "http://[::1]:11434"] {
            XCTAssertNoThrow(try LocalQuerySettings(endpoint: endpoint).baseURL())
        }
        for endpoint in ["https://example.com", "http://localhost.evil.test", "http://localhost@evil.test", "http://192.168.1.1:11434", "http://localhost/path", "http://localhost?redirect=1", "http://user:password@localhost"] {
            XCTAssertThrowsError(try LocalQuerySettings(endpoint: endpoint).baseURL())
        }
    }

    func testSettingsUseSeparatePreferences() throws {
        let suite = "LocalQueryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LocalQuerySettings.load(from: defaults).model, LocalQuerySettings.defaultModel)
        XCTAssertTrue(LocalQuerySettings.load(from: defaults).autoStart)
        defaults.set(false, forKey: LocalQuerySettings.autoStartKey)
        XCTAssertFalse(LocalQuerySettings.load(from: defaults).autoStart)
        defaults.set("test-model", forKey: LocalQuerySettings.modelKey)
        defaults.set(300, forKey: LocalQuerySettings.timeoutKey)
        XCTAssertEqual(LocalQuerySettings.load(from: defaults).model, "test-model")
        XCTAssertEqual(LocalQuerySettings.load(from: defaults).timeout, 300)
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.contains(LocalQuerySettings.modelKey))
    }

    func testStructuredSQLIsDecoded() throws {
        let response = try OllamaQueryClient.decodeGeneration(response(sql: " SELECT ID FROM APP.ORDERS "))
        XCTAssertEqual(response.query, "SELECT ID FROM APP.ORDERS")
    }

    func testErrorsAndIncompleteResponsesCannotReplaceSQL() throws {
        for data in [try response(sql: ""), try response(sql: "SELECT 1", error: "Select a table"),
                     try response(sql: "SELECT 1", reason: "length"), try response(sql: "SELECT 1", done: false),
                     try response(sql: "```sql\nSELECT 1\n```"), Data("invalid".utf8)] {
            XCTAssertThrowsError(try OllamaQueryClient.decodeGeneration(data))
        }
    }

    func testRelevantTableAndCompositeRelationshipAreIncluded() throws {
        let schema = QueryDatabaseSchema(
            schema: CompletionSchema(schemas: ["APP"], tables: ["APP": [
                CompletionTable(name: "ORDERS", columns: [CompletionColumn(name: "CUSTOMER_ID", typeName: "NUMBER")]),
                CompletionTable(name: "CUSTOMERS", columns: [CompletionColumn(name: "ID", typeName: "NUMBER")]),
                CompletionTable(name: "UNRELATED", columns: [CompletionColumn(name: "SECRET", typeName: "CLOB")]),
            ]], functions: [], types: []),
            keys: [QuerySchemaKey(schema: "APP", table: "ORDERS", name: "FK",
                                  columns: ["CUSTOMER_ID", "TENANT_ID"], referencedSchema: "APP",
                                  referencedTable: "CUSTOMERS", referencedColumns: ["ID", "TENANT_ID"])]
        )
        let context = try LocalQueryContextBuilder.build(schema: schema, backendName: "Oracle", database: "APP",
                                                        serverVersion: "19c", selectedPath: nil,
                                                        instruction: "Show ORDERS", currentQuery: "")
        XCTAssertTrue(context.contains("\"APP\".\"ORDERS\""))
        XCTAssertTrue(context.contains("(\"CUSTOMER_ID\", \"TENANT_ID\") REFERENCES \"APP\".\"CUSTOMERS\" (\"ID\", \"TENANT_ID\")"))
        XCTAssertFalse(context.contains("SECRET"))
        XCTAssertTrue(context.contains("omitted"))
        XCTAssertFalse(context.contains("Host:"))
    }

    func testEmptySchemaRequiresUserAction() {
        XCTAssertThrowsError(try LocalQueryContextBuilder.build(schema: QueryDatabaseSchema(schema: .empty),
                                                               backendName: "Oracle", database: "APP", serverVersion: nil,
                                                               selectedPath: nil, instruction: "Show rows", currentQuery: ""))
    }

    private func response(sql: String, error: String = "", reason: String = "stop", done: Bool = true) throws -> Data {
        let output = try JSONSerialization.data(withJSONObject: ["sql": sql, "unavailableReason": error])
        return try JSONSerialization.data(withJSONObject: [
            "message": ["role": "assistant", "content": String(decoding: output, as: UTF8.self)],
            "done": done, "done_reason": reason,
        ])
    }
}
