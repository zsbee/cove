import Foundation
import OracleNIO

extension OracleBackend {
    func fetchQuerySchema(database: String) async throws -> QueryDatabaseSchema {
        try await client.withConnection { conn in
            // Query editor databases represent Oracle owners, not service names.
            let owner = database.isEmpty
                ? "SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')"
                : "'\(database.replacingOccurrences(of: "'", with: "''"))'"
            let rows = try await conn.execute("""
                SELECT owner, table_name, column_name,
                    data_type || CASE
                        WHEN data_precision IS NOT NULL THEN '(' || data_precision ||
                            CASE WHEN data_scale IS NOT NULL THEN ',' || data_scale END || ')'
                        WHEN data_type IN ('CHAR', 'VARCHAR2', 'NCHAR', 'NVARCHAR2') THEN '(' || char_length || ')'
                    END
                FROM all_tab_columns
                WHERE owner = \(owner)
                ORDER BY owner, table_name, column_id
                """)
            var tables: [String: [String: [CompletionColumn]]] = [:]
            for try await (schema, table, column, type) in rows.decode((String, String, String, String).self) {
                tables[schema, default: [:]][table, default: []].append(CompletionColumn(name: column, typeName: type))
            }
            let completionTables = tables.mapValues { tables in
                tables.map { CompletionTable(name: $0.key, columns: $0.value) }.sorted { $0.name < $1.name }
            }
            let keyRows = try await conn.execute("""
                SELECT c.owner, c.table_name, c.constraint_name, cc.column_name, c.constraint_type,
                    r.owner, r.table_name, rc.column_name
                FROM all_constraints c
                JOIN all_cons_columns cc ON cc.owner = c.owner AND cc.constraint_name = c.constraint_name
                    AND cc.table_name = c.table_name
                LEFT JOIN all_constraints r ON r.owner = c.r_owner AND r.constraint_name = c.r_constraint_name
                LEFT JOIN all_cons_columns rc ON rc.owner = r.owner AND rc.constraint_name = r.constraint_name
                    AND rc.table_name = r.table_name AND rc.position = cc.position
                WHERE c.owner = \(owner) AND c.constraint_type IN ('P', 'R') AND c.status = 'ENABLED'
                ORDER BY c.owner, c.table_name, c.constraint_name, cc.position
                """)
            var keys: [QuerySchemaKey] = []
            for try await row in keyRows {
                let values = row.values
                guard values.count == 8,
                      let schema = values[0], let table = values[1], let name = values[2], let column = values[3] else { continue }
                // Inaccessible referenced constraints must not be mistaken for primary keys.
                if values[4] == "R", values[5] == nil || values[6] == nil || values[7] == nil { continue }
                if let last = keys.last, last.schema == schema, last.table == table, last.name == name {
                    keys[keys.count - 1].columns.append(column)
                    if let reference = values[7] { keys[keys.count - 1].referencedColumns.append(reference) }
                } else {
                    keys.append(QuerySchemaKey(
                        schema: schema, table: table, name: name, columns: [column],
                        referencedSchema: values[5], referencedTable: values[6],
                        referencedColumns: values[7].map { [$0] } ?? []
                    ))
                }
            }
            return QueryDatabaseSchema(
                schema: CompletionSchema(schemas: tables.keys.sorted(), tables: completionTables, functions: [], types: []),
                keys: keys,
                dialectNotes: "Oracle SQL. Tables and views from ALL_TAB_COLUMNS for the active owner only. Synonyms and other owners are not included. DUAL is an available Oracle built-in table."
            )
        }
    }
}
