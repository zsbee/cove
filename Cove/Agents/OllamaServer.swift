import Foundation

@MainActor
final class OllamaServer {
    static let shared = OllamaServer()

    private let executable: () -> String?
    private var processes: [String: Process] = [:]
    private var startups: [String: Task<Void, Error>] = [:]

    init(executable: (() -> String?)? = nil) {
        self.executable = executable ?? Self.installedExecutable
    }

    func ensureRunning(settings: LocalQuerySettings) async throws {
        guard settings.autoStart else { return }
        let url = try settings.baseURL()
        let key = url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let startup = startups[key] {
            try await startup.value
            return
        }
        let task = Task { try await startIfNeeded(settings: settings, key: key) }
        startups[key] = task
        defer { startups[key] = nil }
        try await task.value
    }

    func stopOwnedServers() {
        for task in startups.values { task.cancel() }
        startups.removeAll()
        // Never stop a server discovered on the port: other apps may be using it.
        for process in processes.values where process.isRunning { process.terminate() }
        processes.removeAll()
    }

    private func startIfNeeded(settings: LocalQuerySettings, key: String) async throws {
        var probeSettings = settings
        probeSettings.timeout = 1
        let client = OllamaQueryClient(settings: probeSettings)
        if (try? await client.installedModels()) != nil { return }
        try Task.checkCancellation()

        let url = try settings.baseURL()
        guard let host = url.host else {
            throw QueryAgentError.launchUnavailable("The local Ollama address is invalid.")
        }
        let process: Process
        if let owned = processes[key], owned.isRunning {
            process = owned
        } else {
            guard let executablePath = executable() else {
                throw QueryAgentError.launchUnavailable("Install Ollama to use local AI. Cove will start it automatically once installed.")
            }
            process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["serve"]
            var environment = ProcessInfo.processInfo.environment
            environment["PATH"] = ExecutableResolver.processPath
            let listenHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
            environment["OLLAMA_HOST"] = "\(listenHost):\(url.port ?? 80)"
            environment["OLLAMA_NO_CLOUD"] = "1"
            process.environment = environment
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        do {
            if !process.isRunning { try process.run() }
            processes[key] = process
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while ContinuousClock.now < deadline {
                try Task.checkCancellation()
                if (try? await client.installedModels()) != nil { return }
                if !process.isRunning {
                    throw QueryAgentError.launchUnavailable("Ollama could not start (exit \(process.terminationStatus)). Check that the local port is free and Ollama is installed correctly.")
                }
                try await Task.sleep(for: .milliseconds(200))
            }
            throw QueryAgentError.launchUnavailable("Ollama did not become ready within 15 seconds. Try again in Local AI Settings.")
        } catch {
            if process.isRunning { process.terminate() }
            processes[key] = nil
            if error is CancellationError { throw CancellationError() }
            if let error = error as? QueryAgentError { throw error }
            throw QueryAgentError.launchUnavailable("Cove could not launch Ollama: \(error.localizedDescription)")
        }
    }

    private static func installedExecutable() -> String? {
        if let path = ExecutableResolver.resolve("ollama") { return path }
        let applications = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
        return applications.map { $0.appendingPathComponent("Ollama.app/Contents/Resources/ollama").path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
