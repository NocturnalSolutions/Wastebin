import Foundation
import Kitura
import SwiftKuerySQLite
import SwiftKuery
import KituraStencil
import Configuration

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
r.setDefault(templateEngine: StencilTemplateEngine())

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
