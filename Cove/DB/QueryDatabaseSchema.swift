import Foundation

struct QuerySchemaKey: Sendable {
    let schema: String
    let table: String
    let name: String
    var columns: [String]
    let referencedSchema: String?
    let referencedTable: String?
    var referencedColumns: [String]
}

struct QueryDatabaseSchema: Sendable {
    let schema: CompletionSchema
    var keys: [QuerySchemaKey] = []
    var dialectNotes = ""
}
