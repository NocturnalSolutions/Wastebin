import Foundation
import Kitura
import WastebinApp

// MARK: Start Kitura
let wastebin = WastebinApp()
let port = wastebin.config["port"] as? Int ?? 8080
Kitura.addHTTPServer(onPort: port, with: wastebin.generateRouter())
Kitura.run()
