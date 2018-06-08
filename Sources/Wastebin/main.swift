import Foundation
import Kitura
import SwiftKuerySQLite
import SwiftKuery
import KituraStencil
import Configuration
import Stencil

// MARK: Configuration Initialization

let config = ConfigurationManager()

// Initial config
config.load([
    // Config file location
    "config": "~/.wastebin.json",
    // Template directory path (currently unused)
    "template-path": nil,
    // Database file path
    "database-path": "~/Databases/wastebin.sqlite",
    // IP port
    "port": nil,
    // Resource path (for CSS/JS files, etc)
    "resource-path": "http://localhost:8081/",
    // Maximum paste body size in chars
    "max-size": 8192
    ])

// Load CLI arguments first because an overriding config file path may have been
// specified
config.load(.commandLineArguments)
if let configFileLoc = config["config"] as? String {
    config.load(file: configFileLoc)
}

// Load CLI arguments again because we want those to override settings in the
// config file
config.load(.commandLineArguments)

// Initialize the database connection
guard let dbPath = config["database-path"] as? String else {
    print("Failure opening database: Can't determine database file path")
    exit(ExitCodes.noDatabaseFile.rawValue)
}

let nsDbPath = NSString(string: dbPath).expandingTildeInPath
// Redundant type label below is required to avoid a segfault on compilation for
// some effing reason.
let expandedDbPath: String = String(nsDbPath)
let dbCxn = SQLiteConnection(filename: expandedDbPath)
dbCxn.connect() { error in
    if let error = error {
        print("Failure opening database: \(error.description)")
        exit(ExitCodes.noDatabaseFile.rawValue)
    }
}

// Hard code syntax mode info for now. Maybe do this in config later?
// This is "Any" because that's what Stencil wants and we're not really using
// it elsewhere.
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

// Default context array for Stencil
let defaultCtxt: [String: Any] = [
    "modes": modes,
    "resourceDir": config["resource-path"] as? String as Any,
]

// MARK: Router Initialization

let r = Router()
let ext = Extension()
// I'd rather do sanitizing via a computed property on the Paste object, but
// Stencil doesn't work with computed properties:
// https://github.com/stencilproject/Stencil/issues/219
// So as a workaround, implement our desired functionality using a Stencil
// filter.
ext.registerFilter("webSanitize") { value in
    guard let value = value else {
        return "" as Any?
    }
    return String(describing: value).webSanitize() as Any?
}
ext.registerFilter("truncAndSanitize") { value in
    guard let value = value else {
        return "" as Any?
    }
    let string = String(describing: value)
    if string.count > 50 {
        let idx = string.index(string.startIndex, offsetBy: 200)
        return String(string.prefix(through: idx)).webSanitize()
    }
    return string.webSanitize()
}
r.setDefault(templateEngine: StencilTemplateEngine(extension: ext))

// Store the regex for a UUID for later reference
let uuidPattern = "[\\dA-F]{8}-[\\dA-F]{4}-[\\dA-F]{4}-[\\dA-F]{4}-[\\dA-F]{12}"

// Front page: Show a form for a new paste
r.get("/") { request, response, next in
    response.headers.setType("text/html", charset: "utf-8")
    try response.render("new-paste", context: defaultCtxt)
    next()
}

// Display a paste
r.get("/:uuid(" + uuidPattern + ")") { request, response, next in
    guard let uuid = request.parameters["uuid"] else {
        try response.status(.notFound).end()
        next()
        return
    }

    do {
        let paste = try Paste.load(fromUuid: uuid)
        response.headers.setType("text/html", charset: "utf-8")
        let context: [String: Any] = ["paste": paste]
        try response.render("paste", context: context.merging(defaultCtxt) { _, new in new })
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

// Submit handler for new paste
r.post("/new", middleware: BodyParserMultiValue())
r.post("/new") { request, response, next in
    guard let postBody = request.body?.asURLEncodedMultiValue, let body = postBody["body"]?.first, let mode = postBody["mode"]?.first else {
        try response.status(.unprocessableEntity).end()
        next()
        return
    }

    guard let maxSize = config["max-size"] as? Int else {
        try response.status(.internalServerError).end()
        next()
        return
    }

    let newPaste = Paste(raw: body, mode: mode)

    let pasteBodySize = body.count
    guard pasteBodySize <= maxSize else {
        let context: [String: Any] = [
            "paste": newPaste,
            "error": "pasteBodyCount",
            "pasteBodyLimit": maxSize,
            "pasteBodySize": pasteBodySize,
        ]
        try response.render("new-paste", context: context.merging(defaultCtxt) { _, new in new })
        next()
        return
    }

    do {
        try newPaste.save()
        try response.redirect("/" + newPaste.uuid.uuidString)
    }
    catch {
        try response.status(.unprocessableEntity).end()
    }
    next()
}

// List posts
r.get("/list") { request, response, next in
    let page: Int
    if let pageStr = request.queryParametersMultiValues["page"]?.first {
        page = Int(pageStr) ?? 1
    }
    else {
        page = 1
    }
    let startFrom = (page - 1) * Paste.pastesPerListPage
    let pastesToShow = Paste.loadList(from: startFrom)

    // Build pager
    let pasteCount = Paste.pasteCount()
    let pageCount = Int(ceil(Float(pasteCount) / Float(Paste.pastesPerListPage)))
    let pages = [Int](1...pageCount)

    let context: [String: Any] = [
        "pastes": pastesToShow,
        "pages": pages,
        "currentPage": page,
        "pasteCount": pasteCount,
        ]
    response.headers.setType("text/plain", charset: "utf-8")
    try response.render("list", context: context.merging(defaultCtxt) { _, new in new })
}

// Install database for a new site
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

// MARK: Start Kitura

let port = config["port"] as? Int ?? 8080
Kitura.addHTTPServer(onPort: port, with: r)
Kitura.run()
