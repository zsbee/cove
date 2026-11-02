import Foundation

struct QueryHistoryStoreIO {
    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Cove/query-history.json")
    }

    let fileURL: URL

    private struct Document: Codable {
        var version = 1
        var entries: [QueryHistoryEntry]
    }

    private enum HistoryError: LocalizedError {
        case unsupportedVersion(Int)
        case invalidEntries

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                "Unsupported query history version: \(version)."
            case .invalidEntries:
                "The query history contains invalid or duplicate entries."
            }
        }
    }

    func load() throws -> [QueryHistoryEntry] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.version == 1 else { throw HistoryError.unsupportedVersion(document.version) }
        let entries = document.entries
        guard Set(entries.map(\.id)).count == entries.count,
              Set(entries.map(\.sql)).count == entries.count,
              entries.allSatisfy({ !$0.sql.isEmpty && $0.sql == $0.sql.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
            throw HistoryError.invalidEntries
        }
        return entries
    }

    func save(_ entries: [QueryHistoryEntry]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Document(entries: entries))
        try data.write(to: fileURL, options: .atomic)
    }
}
