import SwiftUI

struct LocalQuerySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LocalQuerySettings.endpointKey) private var endpoint = LocalQuerySettings.defaultEndpoint
    @AppStorage(LocalQuerySettings.modelKey) private var model = LocalQuerySettings.defaultModel
    @AppStorage(LocalQuerySettings.timeoutKey) private var timeout = 180.0
    @AppStorage(LocalQuerySettings.autoStartKey) private var autoStart = true
    @State private var models: [String] = []
    @State private var checking = false
    @State private var status = ""
    @State private var failed = false
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Local SQL Assistant").font(.headline)
            Text("Ollama runs a downloaded model on your Mac. Cove only allows localhost endpoints and rejects cloud models. No automatic cloud fallback.")
                .foregroundStyle(.secondary)

            Form {
                Toggle("Start Ollama automatically with Cove", isOn: $autoStart)
                TextField("Ollama address", text: $endpoint)
                TextField("Model", text: $model)
                if !models.isEmpty {
                    Picker("Installed models", selection: $model) {
                        if !models.contains(model) { Text(model).tag(model) }
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }
                }
                Stepper("Timeout: \(Int(timeout)) seconds", value: $timeout, in: 30...600, step: 30)
            }
            .disabled(checking)

            Text(autoStart
                 ? "Cove starts installed Ollama in the background and stops only servers it started when Cove quits. An existing Ollama server is left running. No terminal is needed for everyday use."
                 : "Automatic startup is disabled. Start Ollama yourself before using local AI.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("One-time model download, if not already installed:\nollama pull qwen2.5-coder:14b\n\nSmaller alternative: qwen2.5-coder:7b")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

            Text("Cove supplies schema definitions, keys, your request, and the current SQL—not database passwords or result rows. Generated SQL is never run automatically. AI settings are separate from saved connections.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !status.isEmpty {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(failed ? Color.red : Color.secondary)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Test Connection") { testConnection() }.disabled(checking)
                if checking { ProgressView().controlSize(.small) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onDisappear { checkTask?.cancel() }
        .onChange(of: endpoint) { status = "" }
        .onChange(of: model) { status = "" }
    }

    private func testConnection() {
        checking = true
        failed = false
        status = "Checking local Ollama…"
        let settings = LocalQuerySettings(endpoint: endpoint, model: model, timeout: 10, autoStart: autoStart)
        checkTask = Task {
            defer { checking = false }
            do {
                try await OllamaServer.shared.ensureRunning(settings: settings)
                try Task.checkCancellation()
                let client = OllamaQueryClient(settings: settings)
                models = try await client.installedModels()
                _ = try await client.testConnection()
                status = "Connected. \(model) is installed locally."
            } catch is CancellationError {
                status = ""
            } catch {
                failed = true
                status = error.localizedDescription
            }
        }
    }
}
