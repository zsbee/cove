import Foundation

struct ConnectionSession: Codable {
    var selectedPath: [String]?
    var expandedPaths: Set<[String]>?
    var showInspector: Bool?
    var showQueryEditor: Bool?
    var queryDatabase: String?
}

struct EnvironmentSession: Codable {
    var activeConnectionId: UUID?
}

// MARK: - Multi-tab session models

struct TabSession: Codable {
    var tabId: UUID
    var showSidebar: Bool
    var sidebarWidth: CGFloat?
    var selectedEnvironment: ConnectionEnvironment?
    var environments: [String: EnvironmentSession]?
    var connectionSessions: [String: ConnectionSession]?
    var showQueryHistory: Bool?
}

struct MultiTabSessionState: Codable {
    var tabs: [TabSession]
}

enum SessionStoreIO {
    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return support.appendingPathComponent("Cove/session.json")
    }

    static func load() -> MultiTabSessionState? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let multi = try? JSONDecoder().decode(MultiTabSessionState.self, from: data),
              !multi.tabs.isEmpty else {
            return nil
        }
        return multi
    }

    static func saveMulti(_ state: MultiTabSessionState) {
        guard let url = fileURL else { return }
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[Cove] Failed to save session: \(error)")
        }
    }
}
