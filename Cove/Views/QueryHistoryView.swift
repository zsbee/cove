import SwiftUI
import AppKit

struct QueryHistoryView: View {
    @Environment(AppState.self) private var state
    @State private var search = ""
    @State private var confirmClear = false
    @State private var entryToDelete: QueryHistoryEntry?

    private var history: QueryHistoryStore { state.shared.queryHistory }

    private var selectedEntry: QueryHistoryEntry? {
        history.entries.first { $0.id == state.selectedHistoryID }
    }

    private func matchesSearch(_ entry: QueryHistoryEntry) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || entry.sql.localizedStandardContains(term)
    }

    var body: some View {
        @Bindable var state = state
        let starred = history.starred.filter(matchesSearch)
        let recent = history.recent.filter(matchesSearch)

        VStack(spacing: 0) {
            header
            searchField

            if !history.persistenceError.isEmpty {
                Label(history.persistenceError, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            VSplitView {
                List(selection: $state.selectedHistoryID) {
                    if !starred.isEmpty {
                        Section("Starred") {
                            ForEach(starred) { entry in
                                historyRow(entry).tag(entry.id)
                            }
                        }
                    }
                    if !recent.isEmpty {
                        Section("Recent") {
                            ForEach(recent) { entry in
                                historyRow(entry).tag(entry.id)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .overlay {
                    if starred.isEmpty && recent.isEmpty {
                        ContentUnavailableView(
                            history.entries.isEmpty ? "No Query History" : "No Matching Queries",
                            systemImage: "clock.arrow.circlepath",
                            description: Text(history.entries.isEmpty
                                ? "Run a query or star the current SQL block to save it here."
                                : "Try a different search.")
                        )
                    }
                }
                .frame(minHeight: 140)

                preview
                    .frame(minHeight: 160, idealHeight: 240)
            }
        }
        .confirmationDialog("Clear recent query history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear Recent", role: .destructive) { history.clearRecent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all unstarred queries from every tab. Starred queries are kept.")
        }
        .alert("Delete Starred Query?", isPresented: Binding(
            get: { entryToDelete != nil },
            set: { if !$0 { entryToDelete = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let entry = entryToDelete { history.remove(entry.id) }
                entryToDelete = nil
            }
            Button("Cancel", role: .cancel) { entryToDelete = nil }
        } message: {
            Text("This removes the starred query from every tab and cannot be undone.")
        }
        .onChange(of: history.entries) { _, entries in
            if let id = state.selectedHistoryID, !entries.contains(where: { $0.id == id }) {
                state.selectedHistoryID = nil
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Query History")
                .font(.headline)
            Spacer()
            Menu {
                Button("Clear Recent…", role: .destructive) { confirmClear = true }
                    .disabled(history.recent.isEmpty)
            } label: {
                Label("History Actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button {
                state.toggleQueryHistory()
            } label: {
                Label("Close Query History", systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .help("Close Query History")
        }
        .padding(12)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search queries", text: $search)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search query history")
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Label("Clear Search", systemImage: "xmark.circle.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(7)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func historyRow(_ entry: QueryHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                history.setStarred(!entry.isStarred, id: entry.id)
            } label: {
                Label(entry.isStarred ? "Unstar Query" : "Star Query", systemImage: entry.isStarred ? "star.fill" : "star")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(entry.isStarred ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(entry.isStarred ? "Unstar Query" : "Star Query")

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.sql)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let date = entry.lastExecutedAt {
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not run yet")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(entry.isStarred ? "Unstar Query" : "Star Query") {
                history.setStarred(!entry.isStarred, id: entry.id)
            }
            Button("Copy Query") { copy(entry.sql) }
            Button("Insert in Editor") { state.insertHistoryQuery(entry.sql) }
                .disabled(state.connection == nil || state.query.agentExecuting)
            Divider()
            Button("Delete Query", role: .destructive) {
                if entry.isStarred {
                    entryToDelete = entry
                } else {
                    history.remove(entry.id)
                }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            if let entry = selectedEntry {
                ScrollView([.horizontal, .vertical]) {
                    Text(entry.sql)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                Divider()
                HStack {
                    Button("Copy", systemImage: "doc.on.doc") { copy(entry.sql) }
                    Spacer(minLength: 0)
                    Button("Insert in Editor") { state.insertHistoryQuery(entry.sql) }
                        .disabled(state.connection == nil || state.query.agentExecuting)
                        .help(state.connection == nil ? "Connect to a database to insert this query" : "Append to the editor without running")
                }
                .controlSize(.small)
                .padding(10)
            } else {
                Text("Select a query to preview its full text.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
            }
        }
    }

    private func copy(_ sql: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sql, forType: .string)
    }
}
