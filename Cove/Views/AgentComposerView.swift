import SwiftUI

struct QueryEditorControls: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 8) {
            if !state.query.agentError.isEmpty {
                Text(state.query.agentError)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(state.query.agentError)
            } else if !state.query.error.isEmpty {
                Text(state.query.error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            } else if !state.query.agentStatus.isEmpty {
                Text(state.query.agentStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if state.query.agentExecuting || state.query.executing {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer(minLength: 0)

            Button {
                state.starCurrentQuery()
            } label: {
                Label("Star Current Query", systemImage: "star")
                    .labelStyle(.iconOnly)
            }
            .disabled(state.query.runnableSQL.isEmpty)
            .help("Save the current SQL selection or block to Starred without running it")

            if state.query.agentInputVisible {
                runCurrentButton
            } else {
                runCurrentButton
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .controlSize(.small)
        .padding(8)
    }

    private var runCurrentButton: some View {
        Button {
            state.executeQuery()
        } label: {
            Label("Run Current", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
    }
}

struct AgentComposer: View {
    @Environment(AppState.self) private var state
    @State private var promptHeight: CGFloat = 20
    @State private var showLocalSettings = false

    private var placeholder: String {
        if let selected = state.query.selectedAgent {
            "Ask \(selected.shortName) to create or edit this query"
        } else {
            "Ask an agent to create or edit this query"
        }
    }

    private var generationDisabled: Bool {
        state.query.selectedAgent == nil
            || state.query.agentPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || state.query.agentExecuting
    }

    var body: some View {
        @Bindable var query = state.query

        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AgentPromptTextView(
                    text: $query.agentPrompt,
                    placeholder: placeholder,
                    isEnabled: !query.agentExecuting && query.selectedAgent != nil,
                    height: $promptHeight,
                    autoFocus: query.agentInputVisible,
                    focusTrigger: query.agentFocusGeneration,
                    onSubmit: {
                        if !generationDisabled {
                            state.generateQueryWithAgent()
                        }
                    },
                    onCancel: {
                        state.cancelQueryAgentGeneration()
                    }
                )
                    .frame(height: promptHeight)
                    .padding(.trailing, 26)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                Button {
                    state.cancelQueryAgentGeneration()
                } label: {
                    Label("Close Agent Mode", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close Agent Mode")
            }

            HStack(spacing: 8) {
                AgentPicker()

                if query.selectedAgent == .ollama {
                    Button {
                        showLocalSettings = true
                    } label: {
                        Label("Local AI Settings", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                    .help("Configure and test local Ollama")
                    .disabled(query.agentExecuting)

                    Button {
                        state.refreshLocalQuerySchema()
                    } label: {
                        Label("Refresh AI Schema", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .help("Reload database metadata on the next generation")
                    .disabled(query.agentExecuting)
                }

                Spacer(minLength: 0)

                if query.agentExecuting {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    state.generateQueryWithAgent()
                } label: {
                    Label("Generate", systemImage: "arrow.up")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(generationDisabled)
                .help("Generate Query")
            }
        }
        .controlSize(.small)
        .padding(14)
        .sheet(isPresented: $showLocalSettings) { LocalQuerySettingsView() }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

private struct AgentPicker: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var query = state.query

        Menu {
            ForEach(QueryAgentKind.allCases) { agent in
                Button {
                    state.selectQueryAgent(agent)
                } label: {
                    Label(agent.displayName, systemImage: agent.systemImage)
                }
            }
        } label: {
            if let selected = query.selectedAgent {
                Label(selected.displayName, systemImage: selected.systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Label("Select Agent", systemImage: "wand.and.sparkles")
                    .labelStyle(.titleAndIcon)
            }
        }
        .menuStyle(.button)
        .controlSize(.small)
        .fixedSize()
        .disabled(state.query.agentExecuting)
    }
}
