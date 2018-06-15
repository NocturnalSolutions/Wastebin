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

    static let pastesPerListPage = 50

    enum PasteError: Error {
        case missingFieldOnDbRow
        case castingFailed
        case alreadySaved
        case notFoundForUuid
    }

    
    static var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Initialize a paste from a database row
    init(fromRow row: [String: Any?]) throws {
        guard let uuidStr = row["uuid"] as? String, let dateStr = row["date"] as? String, let raw = row["raw"] as? String, let mode = row["mode"] as? String else {
            throw PasteError.missingFieldOnDbRow
        }

        guard let uuid = UUID(uuidString: uuidStr), let date = Paste.dateFormatter.date(from: dateStr) else {
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

        WastebinApp.dbCxn?.execute(query: q) { queryResult in
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

    /// Load a list of pastes
    static func loadList(from: Int) -> [Paste] {
        let pasteTable = PasteTable()
        // mid() currently broken in Swift-Kuery-SQLite
//        let q = Select(pasteTable.uuid, pasteTable.date, mid(pasteTable.raw, start: 0, length: 50).as("raw"), from: pasteTable)
        let q = Select(pasteTable.columns, from: pasteTable)
        .order(by: .DESC(pasteTable.date))
        .offset(from)
        .limit(to: pastesPerListPage)

        var result: [Paste] = []
        WastebinApp.dbCxn?.execute(query: q) { queryResult in
            if let rows = queryResult.asRows {
                for row in rows {
                    do {
                        let paste = try Paste(fromRow: row)
                        result.append(paste)
                    }
                    catch {
                        // Hmm, log something, I guess
                    }
                }
            }
        }
        return result
    }

    /// Count total pastes
    static func pasteCount() -> Int {
        let pasteTable = PasteTable()
        let q = Select(count(pasteTable.uuid).as("count"), from: pasteTable)
        var pasteCount = 0
        WastebinApp.dbCxn?.execute(query: q) {queryResult in
            // Awkward multi-level unwrapping
            if let result = queryResult.asRows,
                let row = result.first,
                let value = row["count"],
                let count = value
            {
                pasteCount = Int(String(describing: count)) ?? 0
            }
        }
        return pasteCount
    }

    /// Save an unsaved paste
    func save() throws {
        guard date == nil else {
            throw PasteError.alreadySaved
        }
        let pasteTable = PasteTable()
        let i = Insert(into: pasteTable, valueTuples: [
            (pasteTable.uuid, uuid.uuidString),
            (pasteTable.date, Paste.dateFormatter.string(from: Date())),
            (pasteTable.raw, raw),
            (pasteTable.mode, mode)
        ])
        var dbError: Error?
        WastebinApp.dbCxn?.execute(query: i) { queryResult in
            if let error = queryResult.asError {
                dbError = error
            }
        }

        if let dbError = dbError {
            throw dbError
        }
    }

    func delete() throws {
        let pasteTable = PasteTable()
        let d = Delete(from: pasteTable)
        .where(pasteTable.uuid == uuid.uuidString)
        var dbError: Error?
        WastebinApp.dbCxn?.execute(query: d) { queryResult in
            if let error = queryResult.asError {
                dbError = error
            }
        }
        if let dbError = dbError {
            throw dbError
        }
    }
}
