import Foundation

struct QueryHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let sql: String
    let createdAt: Date
    var lastExecutedAt: Date?
    var starredAt: Date?

    var isStarred: Bool { starredAt != nil }
    var recency: Date { lastExecutedAt ?? createdAt }
}

@Observable
@MainActor
final class QueryHistoryStore {
    static let recentLimit = 100

    private(set) var entries: [QueryHistoryEntry] = []
    private(set) var persistenceError = ""
    private let storage: QueryHistoryStoreIO
    private var canSave = true

    var starred: [QueryHistoryEntry] {
        entries.filter(\.isStarred).sorted {
            if $0.starredAt != $1.starredAt { return ($0.starredAt ?? .distantPast) > ($1.starredAt ?? .distantPast) }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    var recent: [QueryHistoryEntry] {
        entries.filter { !$0.isStarred }.sorted {
            if $0.recency != $1.recency { return $0.recency > $1.recency }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    init(fileURL: URL = QueryHistoryStoreIO.defaultFileURL) {
        storage = QueryHistoryStoreIO(fileURL: fileURL)
        do {
            entries = try storage.load()
            pruneRecent()
        } catch {
            // Never replace an unreadable or newer-format history with an empty document.
            canSave = false
            persistenceError = "Could not load query history. The original file is untouched at \(fileURL.path). Move or repair it, then restart Cove. New changes are only kept in memory. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func record(_ sql: String, at date: Date = Date()) -> UUID? {
        let sql = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return nil }

        let id: UUID
        if let index = entries.firstIndex(where: { $0.sql == sql }) {
            entries[index].lastExecutedAt = date
            id = entries[index].id
        } else {
            id = UUID()
            entries.append(QueryHistoryEntry(id: id, sql: sql, createdAt: date, lastExecutedAt: date))
        }
        persist()
        return id
    }

    @discardableResult
    func star(_ sql: String, at date: Date = Date()) -> UUID? {
        let sql = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else { return nil }

        if let entry = entries.first(where: { $0.sql == sql }) {
            if !entry.isStarred { setStarred(true, id: entry.id, at: date) }
            return entry.id
        }

        let id = UUID()
        entries.append(QueryHistoryEntry(id: id, sql: sql, createdAt: date, starredAt: date))
        persist()
        return id
    }

    func setStarred(_ isStarred: Bool, id: UUID, at date: Date = Date()) {
        guard let index = entries.firstIndex(where: { $0.id == id }),
              entries[index].isStarred != isStarred else { return }
        entries[index].starredAt = isStarred ? date : nil
        persist()
    }

    func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    func clearRecent() {
        entries.removeAll { !$0.isStarred }
        persist()
    }

    private func pruneRecent() {
        let retainedIDs = Set(recent.prefix(Self.recentLimit).map(\.id))
        entries.removeAll { !$0.isStarred && !retainedIDs.contains($0.id) }
    }

    private func persist() {
        pruneRecent()
        guard canSave else { return }
        do {
            try storage.save(entries)
            persistenceError = ""
        } catch {
            persistenceError = "Query history changes could not be saved and may be lost when Cove quits. \(error.localizedDescription)"
        }
    }
}
