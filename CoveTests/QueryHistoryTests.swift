import XCTest
@testable import Cove

@MainActor
final class QueryHistoryTests: XCTestCase {
    func testMissingHistoryStartsEmpty() async throws {
        try withHistory { history, _ in
            XCTAssertTrue(history.entries.isEmpty)
            XCTAssertTrue(history.persistenceError.isEmpty)
        }
    }

    func testRecordsSQLWithoutChangingInternalWhitespaceOrCase() async throws {
        try withHistory { history, _ in
            let sql = "SELECT 'Mixed  Case'\nFROM customers;"
            history.record(" \n\(sql)\n ", at: date(1))
            XCTAssertEqual(history.recent.map(\.sql), [sql])
            XCTAssertEqual(history.recent.first?.lastExecutedAt, date(1))
            XCTAssertTrue(history.starred.isEmpty)
        }
    }

    func testBlankQueriesAreIgnored() async throws {
        try withHistory { history, _ in
            XCTAssertNil(history.record(" \n\t "))
            XCTAssertNil(history.star(" \n\t "))
            XCTAssertTrue(history.entries.isEmpty)
        }
    }

    func testRepeatedSQLKeepsIdentityAndMovesToTop() async throws {
        try withHistory { history, _ in
            let id = history.record("SELECT 1", at: date(1))
            history.record("SELECT 2", at: date(2))
            XCTAssertEqual(history.record(" SELECT 1\n", at: date(3)), id)
            XCTAssertEqual(history.recent.map(\.sql), ["SELECT 1", "SELECT 2"])
            XCTAssertEqual(history.recent.first?.createdAt, date(1))
            XCTAssertEqual(history.recent.first?.lastExecutedAt, date(3))
        }
    }

    func testDifferentCaseAndInternalWhitespaceRemainSeparate() async throws {
        try withHistory { history, _ in
            for sql in ["SELECT 'A'", "SELECT 'a'", "SELECT  'A'"] { history.record(sql) }
            XCTAssertEqual(history.entries.count, 3)
        }
    }

    func testStarUnexecutedQueryAndThenRunIt() async throws {
        try withHistory { history, _ in
            let id = try XCTUnwrap(history.star(" SELECT 1 ", at: date(1)))
            XCTAssertNil(history.starred.first?.lastExecutedAt)
            XCTAssertTrue(history.recent.isEmpty)

            XCTAssertEqual(history.record("SELECT 1", at: date(2)), id)
            XCTAssertEqual(history.starred.first?.lastExecutedAt, date(2))
            XCTAssertEqual(history.starred.first?.starredAt, date(1))
            XCTAssertTrue(history.recent.isEmpty)
            XCTAssertEqual(history.entries.count, 1)
        }
    }

    func testStarringExistingQueryDoesNotChangeExecutionTimeOrDuplicate() async throws {
        try withHistory { history, _ in
            let id = history.record("SELECT 1", at: date(1))
            XCTAssertEqual(history.star("SELECT 1", at: date(2)), id)
            XCTAssertEqual(history.star("SELECT 1", at: date(3)), id)
            XCTAssertEqual(history.starred.first?.lastExecutedAt, date(1))
            XCTAssertEqual(history.starred.first?.starredAt, date(2))
            XCTAssertTrue(history.recent.isEmpty)
            XCTAssertEqual(history.entries.count, 1)
        }
    }

    func testStarOrderIsStableWhenQueriesAreRerun() async throws {
        try withHistory { history, _ in
            history.star("SELECT 1", at: date(1))
            history.star("SELECT 2", at: date(2))
            history.record("SELECT 1", at: date(3))
            XCTAssertEqual(history.starred.map(\.sql), ["SELECT 2", "SELECT 1"])
        }
    }

    func testRetentionKeeps100RecentPlusEveryStar() async throws {
        try withHistory { history, _ in
            history.star("SELECT 'saved'", at: date(0))
            for index in 1...105 { history.record("SELECT \(index)", at: date(index)) }
            XCTAssertEqual(history.recent.count, 100)
            XCTAssertEqual(history.entries.count, 101)
            XCTAssertEqual(history.recent.first?.sql, "SELECT 105")
            XCTAssertEqual(history.recent.last?.sql, "SELECT 6")
            XCTAssertEqual(history.starred.map(\.sql), ["SELECT 'saved'"])
        }
    }

    func testUnstarringOldQueryAppliesRecentLimit() async throws {
        try withHistory { history, _ in
            let id = try XCTUnwrap(history.star("SELECT 'old'", at: date(0)))
            for index in 1...100 { history.record("SELECT \(index)", at: date(index)) }
            history.setStarred(false, id: id)
            XCTAssertTrue(history.starred.isEmpty)
            XCTAssertEqual(history.recent.count, 100)
            XCTAssertFalse(history.entries.contains { $0.id == id })
        }
    }

    func testUnstarReturnsToOriginalRecency() async throws {
        try withHistory { history, _ in
            let id = try XCTUnwrap(history.record("SELECT 1", at: date(1)))
            history.record("SELECT 2", at: date(2))
            history.setStarred(true, id: id, at: date(3))
            history.setStarred(false, id: id, at: date(4))
            XCTAssertEqual(history.recent.map(\.sql), ["SELECT 2", "SELECT 1"])
        }
    }

    func testClearRecentAndDeletePersistWithoutRemovingOtherStars() async throws {
        try withHistory { history, url in
            let first = try XCTUnwrap(history.star("SELECT 1"))
            history.star("SELECT 2")
            history.record("SELECT 3")
            history.clearRecent()
            XCTAssertEqual(history.entries.count, 2)
            XCTAssertTrue(history.recent.isEmpty)
            history.remove(first)
            XCTAssertEqual(QueryHistoryStore(fileURL: url).entries.map(\.sql), ["SELECT 2"])
        }
    }

    func testRoundTripRestoresFullSQLDatesAndStars() async throws {
        try withHistory { history, url in
            history.record("SELECT '😀'\nFROM customers;", at: date(1))
            history.star("SELECT 2", at: date(2))
            let restored = QueryHistoryStore(fileURL: url)
            XCTAssertEqual(restored.entries, history.entries)
            XCTAssertEqual(restored.starred, history.starred)
            XCTAssertEqual(restored.recent, history.recent)
            XCTAssertTrue(restored.persistenceError.isEmpty)
        }
    }

    func testCorruptOrNewerHistoryIsNeverOverwritten() async throws {
        try withHistory { _, url in
            for original in [Data("broken json".utf8), Data(#"{"version":2,"entries":[]}"#.utf8)] {
                try original.write(to: url)
                let history = QueryHistoryStore(fileURL: url)
                XCTAssertFalse(history.persistenceError.isEmpty)
                history.record("SELECT 1")
                history.star("SELECT 2")
                history.clearRecent()
                XCTAssertFalse(history.persistenceError.isEmpty)
                XCTAssertEqual(try Data(contentsOf: url), original)
                XCTAssertEqual(history.starred.map(\.sql), ["SELECT 2"])
            }
        }
    }

    func testSaveFailureKeepsInMemoryHistoryAndRecoversOnNextSave() async throws {
        try withHistory { _, url in
            let blockedDirectory = url.deletingLastPathComponent().appending(path: "not-a-directory")
            let blockedURL = blockedDirectory.appending(path: "history.json")
            let history = QueryHistoryStore(fileURL: blockedURL)
            XCTAssertTrue(history.persistenceError.isEmpty)
            try Data("blocking file".utf8).write(to: blockedDirectory)
            history.record("SELECT 1")
            XCTAssertEqual(history.entries.count, 1)
            XCTAssertFalse(history.persistenceError.isEmpty)
            try FileManager.default.removeItem(at: blockedDirectory)
            history.record("SELECT 2")
            XCTAssertTrue(history.persistenceError.isEmpty)
            XCTAssertEqual(QueryHistoryStore(fileURL: blockedURL).entries.count, 2)
        }
    }

    func testDuplicateEntriesArePreservedAsUnreadableRatherThanLoaded() async throws {
        try withHistory { _, url in
            let entry = QueryHistoryEntry(id: UUID(), sql: "SELECT 1", createdAt: date(1))
            try QueryHistoryStoreIO(fileURL: url).save([entry, entry])
            let original = try Data(contentsOf: url)
            let history = QueryHistoryStore(fileURL: url)
            XCTAssertTrue(history.entries.isEmpty)
            XCTAssertFalse(history.persistenceError.isEmpty)
            history.record("SELECT 2")
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testLoadingAppliesRetentionWithoutDroppingStars() async throws {
        try withHistory { _, url in
            let entries = (1...105).map { index in
                QueryHistoryEntry(id: UUID(), sql: "SELECT \(index)", createdAt: date(index), lastExecutedAt: date(index))
            }
            let starred = QueryHistoryEntry(id: UUID(), sql: "SELECT 'saved'", createdAt: date(0), starredAt: date(0))
            try QueryHistoryStoreIO(fileURL: url).save(entries + [starred])
            let restored = QueryHistoryStore(fileURL: url)
            XCTAssertEqual(restored.recent.count, 100)
            XCTAssertEqual(restored.recent.last?.sql, "SELECT 6")
            XCTAssertEqual(restored.starred, [starred])
        }
    }

    func testRunnableSelectionIsSavedInsteadOfEntireEditor() async throws {
        try withHistory { history, _ in
            let query = QueryState()
            query.text = "SELECT 1\n\nSELECT 2"
            query.selectedRange = NSRange(location: 10, length: 8)
            history.record(query.runnableSQL)
            XCTAssertEqual(history.recent.map(\.sql), ["SELECT 2"])
        }
    }

    func testLegacyTabSessionDecodesWithoutHistoryPreference() async throws {
        let json = Data("""
            {"tabId":"\(UUID().uuidString)","showSidebar":true}
            """.utf8)
        let session = try JSONDecoder().decode(TabSession.self, from: json)
        XCTAssertNil(session.showQueryHistory)
    }

    private func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private func withHistory(_ test: (QueryHistoryStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "CoveQueryHistoryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.json")
        try test(QueryHistoryStore(fileURL: url), url)
    }
}
