import Foundation

enum LocalQueryContextBuilder {
    static let characterBudget = 24000

    static func build(
        schema: QueryDatabaseSchema,
        backendName: String,
        database: String,
        serverVersion: String?,
        selectedPath: [String]?,
        instruction: String,
        currentQuery: String
    ) throws -> String {
        struct TableID: Hashable { let schema: String; let table: String }
        let allTables = schema.schema.tables.keys.sorted().flatMap { owner in
            (schema.schema.tables[owner] ?? []).sorted { $0.name < $1.name }.map { (id: TableID(schema: owner, table: $0.name), table: $0) }
        }
        guard !allTables.isEmpty else {
            throw QueryAgentError.invalidResponse("No schema metadata is available. Select a schema containing tables or views, then refresh AI schema.")
        }
        let words = Set((instruction + " " + currentQuery).lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "$" && $0 != "#" }.map(String.init))
        var relevant = Set(allTables.filter { entry in
            words.contains(entry.id.table.lowercased()) ||
                (selectedPath?.first == entry.id.schema && selectedPath?.contains(entry.id.table) == true)
        }.map(\.id))
        // Include one hop of known relationships without expanding the whole graph.
        let initial = relevant
        for key in schema.keys {
            guard let owner = key.referencedSchema, let table = key.referencedTable else { continue }
            let source = TableID(schema: key.schema, table: key.table)
            let target = TableID(schema: owner, table: table)
            if initial.contains(source) || initial.contains(target) {
                relevant.insert(source)
                relevant.insert(target)
            }
        }
        let candidates = relevant.isEmpty ? allTables :
            allTables.filter { initial.contains($0.id) } +
            allTables.filter { relevant.contains($0.id) && !initial.contains($0.id) }
        var lines = [
            "Backend: \(backendName)",
            "Server version: \(serverVersion ?? "unknown; do not assume version-specific features")",
            "Active schema/database: \(database.isEmpty ? schema.schema.schemas.joined(separator: ", ") : database)",
            schema.dialectNotes,
            "Only the complete table definitions below may be used. Identifiers are shown in double quotes.",
        ]
        var included = Set<TableID>()
        var count = lines.joined(separator: "\n").count
        func quote(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        for entry in candidates {
            let columns = entry.table.columns.map { "  \(quote($0.name)) \($0.typeName)" }.joined(separator: ",\n")
            let definition = "TABLE \(quote(entry.id.schema)).\(quote(entry.id.table)) (\n\(columns)\n)"
            guard count + definition.count + 1 <= characterBudget - 4000 else { continue }
            lines.append(definition)
            count += definition.count + 1
            included.insert(entry.id)
        }
        guard !included.isEmpty else {
            throw QueryAgentError.invalidResponse("The selected table definitions exceed the local model context limit. Select a smaller table or narrow your request.")
        }
        for key in schema.keys where included.contains(TableID(schema: key.schema, table: key.table)) {
            let columns = key.columns.map(quote).joined(separator: ", ")
            var line = "KEY \(quote(key.schema)).\(quote(key.table)) (\(columns))"
            if let owner = key.referencedSchema, let table = key.referencedTable {
                guard included.contains(TableID(schema: owner, table: table)), key.columns.count == key.referencedColumns.count else { continue }
                line += " REFERENCES \(quote(owner)).\(quote(table)) (\(key.referencedColumns.map(quote).joined(separator: ", ")))"
            } else {
                line += " PRIMARY KEY"
            }
            guard count + line.count + 1 < characterBudget - 200 else { break }
            lines.append(line)
            count += line.count + 1
        }
        if included.count < allTables.count {
            lines.append("Context is scoped: \(allTables.count - included.count) table definitions omitted. Ask the user to select or name missing tables rather than guessing.")
        }
        return lines.joined(separator: "\n")
    }
}
