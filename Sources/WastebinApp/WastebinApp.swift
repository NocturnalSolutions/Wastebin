import Foundation
import Kitura
import KituraStencil
import Stencil
import SwiftKuerySQLite
import SwiftKuery
import Configuration

public struct WastebinApp {

    public let config: ConfigurationManager
    static var dbCxn: SQLiteConnection? = nil

    public init() {
        // MARK: Configuration Initialization

        config = ConfigurationManager()

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
            "max-size": 8192,
            // Password for administration tasks
            "password": nil
            ])

        // Load CLI arguments first because an overriding config file path may have been
        // specified
        config.load(.commandLineArguments)
        if let configFileLoc = config["config"] as? String {
            config.load(file: configFileLoc)
            // Load CLI arguments again because we want those to override settings in the
            // config file
            config.load(.commandLineArguments)
        }


        // Initialize the database connection
        guard let dbPath = config["database-path"] as? String else {
            print("Failure opening database: Can't determine database file path")
            exit(ExitCodes.noDatabaseFile.rawValue)
        }

        // Ensure a password is defined for admin tasks {
        guard config["password"] != nil else {
            print("Define an administration password!")
            exit(ExitCodes.noPassword.rawValue)
        }

        let nsDbPath = NSString(string: dbPath).expandingTildeInPath
        // Redundant type label below is required to avoid a segfault on compilation for
        // some effing reason.
        let expandedDbPath: String = String(nsDbPath)
        WastebinApp.dbCxn = SQLiteConnection(filename: expandedDbPath)
        WastebinApp.dbCxn?.connect() { error in
            if let error = error {
                print("Failure opening database: \(error.description)")
                exit(ExitCodes.noDatabaseFile.rawValue)
            }
        }
    }

    public func generateRouter() -> Router {
        // Hard code syntax mode info for now. Maybe do this in config later?
        // There are certainly better data structures we could use for this, but this
        // one works well for Stencil. Do better later, though.
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
            ]

        // Default context array for Stencil
        let defaultCtxt: [String: Any] = [
            "modes": modes as Any,
            "resourceDir": config["resource-path"] as? String as Any,
            ]

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

            // Truncation length. Should this be configurable?
            let truncLen = 200

            if string.count > truncLen {
                let idx = string.index(string.startIndex, offsetBy: truncLen)
                return String(string.prefix(through: idx)).webSanitize()
            }
            return string.webSanitize()
        }
        r.setDefault(templateEngine: StencilTemplateEngine(extension: ext))

        // Store the regex for a UUID for later reference
        let uuidPattern = "[\\dA-F]{8}-[\\dA-F]{4}-[\\dA-F]{4}-[\\dA-F]{4}-[\\dA-F]{12}"

        // Init admin checking middleware
        let adminCheck = AdminCheck(adminPass: config["password"] as! String)

        // Parse posts for all POST requests.
        r.post(middleware: BodyParserMultiValue())

        // MARK: Front page
        // Show a form for a new paste
        r.get("/") { request, response, next in
            response.headers.setType("text/html", charset: "utf-8")
            try response.render("new-paste", context: defaultCtxt)
            next()
        }

        // Add middleware to attempt to load the paste for all handlers that
        // need one.
        r.all("/:uuid(" + uuidPattern + ")", allowPartialMatch: true, middleware: PasteLoader())

        // MARK: Display a paste
        r.get("/:uuid(" + uuidPattern + ")") { request, response, next in
            do {
                let paste = request.userInfo["loadedPaste"] as! Paste
                response.headers.setType("text/html", charset: "utf-8")
                let context: [String: Any] = ["paste": paste]
                try response.render("paste", context: context.merging(defaultCtxt) { _, new in new })
            }
            catch {
                try response.send(status: .internalServerError).end()
            }
            next()
        }

        // MARK: Raw view for a paste
        r.get("/:uuid(" + uuidPattern + ")/raw") { request, response, next in
            let paste = request.userInfo["loadedPaste"] as! Paste
            response.headers.setType("text/plain", charset: "utf-8")
            response.send(paste.raw)
            next()
        }

        // MARK: Delete a paste
        r.post("/:uuid(" + uuidPattern + ")/delete", middleware: adminCheck)
        r.post("/:uuid(" + uuidPattern + ")/delete") { request, response, next in
            // Gonna use "as!" here and not feel bad about it because we're
            // already checking if it's set in main.swift
            let adminPassword = self.config["password"] as! String
            guard let postBody = request.body?.asURLEncodedMultiValue, let submittedPw = postBody["password"]?.first, submittedPw == adminPassword else {
                try response.send(status: .forbidden).end()
                next()
                return
            }
            do {
                let paste = request.userInfo["loadedPaste"] as! Paste
                try paste.delete()
                try response.redirect("/")
            }
            catch {
                try response.send(status: .internalServerError).end()
            }
            next()
        }

        // MARK: Submit handler for new paste
        r.post("/new", middleware: BodyParserMultiValue())
        r.post("/new") { request, response, next in
            guard let postBody = request.body?.asMultiPart else {
                try response.send(status: .unprocessableEntity).end()
                next()
                return
            }

            // Look for "body" and "mode" values
            var postedBody: String?
            var postedMode: String?
            for part in postBody {
                if part.name == "body" {
                    postedBody = part.body.asText
                }
                else if part.name == "mode" {
                    postedMode = part.body.asText
                }
            }

            guard let bodyValue = postedBody, let modeValue = postedMode else {
                try response.send(status: .unprocessableEntity).end()
                next()
                return
            }

            guard let maxSize = self.config["max-size"] as? Int else {
                try response.send(status: .internalServerError).end()
                next()
                return
            }

            // Make sure the mode is legitimate
            var existsInModes = false
            for mode in modes {
                if mode["sysname"] == modeValue {
                    existsInModes = true
                    break
                }
            }

            guard existsInModes == true else {
                try response.send(status: .unprocessableEntity).end()
                next()
                return
            }

            let newPaste = Paste(raw: bodyValue, mode: modeValue)

            // Make sure the body's not too big. Note we create the new paste
            // object before measuring this since it's easier to send that paste
            // object, hoewver invalid it may be, back to the template layer so
            // iut can be edited to something legit.
            let pasteBodySize = bodyValue.count
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
                try response.redirect("/" + newPaste.uuid.uuidString, status: .seeOther)
            }
            catch {
                try response.send(status: .unprocessableEntity).end()
            }
            next()
        }

        // MARK: List pastes
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

        // MARK: Install database for a new site
        r.get("/install") { request, response, next in
            let pasteTable = PasteTable()
            pasteTable.create(connection: WastebinApp.dbCxn!) { queryResult in
                if queryResult.success {
                    response.headers.setType("text/plain", charset: "utf-8")
                    response.send("Created table \(pasteTable.tableName)\n")
                }
                else {
                    _ = response.send(status: .internalServerError)
                }
            }
            next()
        }

        return r
    }
}
