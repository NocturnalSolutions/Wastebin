import Foundation
import Kitura
import SwiftKuerySQLite
import SwiftKuery
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
}

// Load CLI arguments again because we want those to override settings in the
// config file
config.load(.commandLineArguments)

// Initialize the database connection
guard let dbPath = config["database-path"] as? String else {
    print("Failure opening database: Can't determine database file path")
    exit(ExitCodes.noDatabaseFile.rawValue)
}

// Ensure a password is defined for admin tasks {
guard let adminPassword = config["password"] as? String else {
    print("Define an administration password!")
    exit(ExitCodes.noPassword.rawValue)
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

// MARK: Start Kitura

let port = config["port"] as? Int ?? 8080
Kitura.addHTTPServer(onPort: port, with: WastebinRouter.generateRouter())
Kitura.run()
