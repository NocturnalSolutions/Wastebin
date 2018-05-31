import Foundation
import Kitura
import SwiftKuerySQLite
import SwiftKuery
import KituraStencil

let r = Router()
r.setDefault(templateEngine: StencilTemplateEngine())

// Store the regex for a UUID for later reference
let uuidPattern = "[\\dA-F]{8}-[\\dA-F]{4}-[\\dA-F]{4}-[\\dA-F]{4}-[\\dA-F]{12}"

let dbPath = NSString(string: "~/wastebin.sqlite").expandingTildeInPath
let dbCxn = SQLiteConnection(filename: String(dbPath))
dbCxn.connect() { error in
    if let error = error {
        print("Failure opening database: \(error.description)")
        exit(1)
    }
}

let modes = [
    ["sysname": "objectivec", "name": "Objective-C"],
    ["sysname": "django", "name": "Django"],
    ["sysname": "go", "name": "Go"],
    ["sysname": "haskell", "name": "Haskell"],
    ["sysname": "java", "name": "Java"],
    ["sysname": "json", "name": "JSON"],
    ["sysname": "markdown", "name": "Markdown"],
    ["sysname": "_plain_", "name": "Plain"],
    ["sysname": "perl", "name": "Perl"],
    ["sysname": "php", "name": "PHP"],
    ["sysname": "python", "name": "Python"],
    ["sysname": "ruby", "name": "Ruby"],
    ["sysname": "sql", "name": "SQL"],
    ["sysname": "swift", "name": "Swift"],
    ["sysname": "xml", "name": "XML"],
] as Any

r.get("/") { request, response, next in
    try response.render("new-paste", context: ["modes": modes])
    next()
}

r.get("/:uuid(" + uuidPattern + ")") { request, response, next in
    guard let uuid = request.parameters["uuid"] else {
        try response.status(.notFound).end()
        next()
        return
    }

    do {
        let paste = try Paste.load(fromUuid: uuid)
        response.headers.setType("text/plain", charset: "utf-8")
        response.send(paste.raw)
    }
    catch {
        switch error {
        case Paste.PasteError.notFoundForUuid:
            try response.status(.notFound).end()
        default:
            try response.status(.internalServerError).end()
        }
    }
    next()
}

r.post("/new", middleware: BodyParserMultiValue())
r.post("/new") { request, response, next in
    guard let postBody = request.body?.asURLEncodedMultiValue, let body = postBody["body"]?.first, let mode = postBody["mode"]?.first else {
        try response.status(.unprocessableEntity).end()
        next()
        return
    }
    let newPaste = Paste(raw: body, mode: mode)
    do {
        try newPaste.save()
        try response.redirect("/" + newPaste.uuid.uuidString)
    }
    catch {
        try response.status(.unprocessableEntity).end()
    }
    next()
    return
}
    
r.get("/install") { request, response, next in
    let pasteTable = PasteTable()
    pasteTable.create(connection: dbCxn) { queryResult in
        if queryResult.success {
            response.headers.setType("text/plain", charset: "utf-8")
            response.send("Created table \(pasteTable.tableName)\n")
        }
        else {
            response.status(.internalServerError)
        }
    }
}

Kitura.addHTTPServer(onPort: 8080, with: r)
Kitura.run()
