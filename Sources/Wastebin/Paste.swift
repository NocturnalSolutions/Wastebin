import Foundation
import SwiftKuery

/// Paste table
class PasteTable: Table {
    let tableName = "pastes"
    let uuid = Column("uuid", UUID.self, primaryKey: true)
    let date = Column("date", Varchar.self, length: 19)
    let raw = Column("raw", String.self)
    let mode = Column("mode", Varchar.self, length: 31)
//    let body = Column("body", String.self)
}

/// Paste struct
struct Paste {
    let uuid: UUID
    let date: Date?
    let raw: String
    let mode: String
    // Damn! Stencil doesn't work with computed properties.
//    public var sanitized: String {
//        return raw.webSanitize()
//    }

    enum PasteError: Error {
        case missingFieldOnDbRow
        case castingFailed
        case alreadySaved
        case notFoundForUuid
    }

    /// Initialize a paste from a database row
    init(fromRow row: [String: Any?]) throws {
        guard let uuidStr = row["uuid"] as? String, let dateStr = row["date"] as? String, let raw = row["raw"] as? String, let mode = row["mode"] as? String else {
            throw PasteError.missingFieldOnDbRow
        }

        let dateFmt = ISO8601DateFormatter()
        guard let uuid = UUID(uuidString: uuidStr), let date = dateFmt.date(from: dateStr) else {
            throw PasteError.castingFailed
        }

        self.uuid = uuid
        self.date = date
        self.raw = raw
        self.mode = mode
    }

    /// Initialize a paste as a "fork" of another paste
    /// @TODO
    // init(asForkOf: Paste)

    /// Initialize a new unsaved paste
    init(raw: String, mode: String) {
        self.raw = raw
        self.mode = mode
        uuid = UUID()
        date = nil
    }

    /// Load a paste from the DB based on the UUID
    static func load(fromUuid uuidString: String) throws -> Paste {
        let pasteTable = PasteTable()
        let q = Select(fields: pasteTable.columns, from: [pasteTable])
            .where(pasteTable.uuid == uuidString)
        var loadedPaste: Paste?
        var dbError: Error?

        dbCxn.execute(query: q) { queryResult in
            if let rows = queryResult.asRows, let row = rows.first {
                do {
                    let paste = try Paste(fromRow: row)
                    loadedPaste = paste
                }
                catch {
                    dbError = error
                }
            }
            else if let error = queryResult.asError {
                dbError = error
            }
        }

        if let dbError = dbError {
            throw dbError
        }
        else if let loadedPaste = loadedPaste {
            return loadedPaste
        }
        else {
            throw PasteError.notFoundForUuid
        }
    }

    /// Save an unsaved paste
    func save() throws {
        guard date == nil else {
            throw PasteError.alreadySaved
        }
        let pasteTable = PasteTable()
        let i = Insert(into: pasteTable, valueTuples: [
            (pasteTable.uuid, uuid.uuidString),
            (pasteTable.date, ISO8601DateFormatter().string(from: Date())),
            (pasteTable.raw, raw),
            (pasteTable.mode, mode)
        ])
        var dbError: Error?
        dbCxn.execute(query: i) { queryResult in
            if let error = queryResult.asError {
                dbError = error
            }
        }

        if let dbError = dbError {
            throw dbError
        }
    }
}
