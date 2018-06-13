import Foundation
import Kitura
import KituraStencil
import Stencil

public struct WastebinRouter {
    static func generateRouter() -> Router {
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

        // Front page: Show a form for a new paste
        r.get("/") { request, response, next in
            response.headers.setType("text/html", charset: "utf-8")
            try response.render("new-paste", context: defaultCtxt)
            next()
        }

        // Display a paste
        r.get("/:uuid(" + uuidPattern + ")") { request, response, next in
            guard let uuid = request.parameters["uuid"] else {
                try response.send(status: .notFound).end()
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
                    try response.send(status: .notFound).end()
                default:
                    try response.send(status: .internalServerError).end()
                }
            }
            next()
        }

        // Delete a paste
        r.post("/:uuid(" + uuidPattern + ")/delete", middleware: BodyParserMultiValue())
        r.post("/:uuid(" + uuidPattern + ")/delete") { request, response, next in
            // Gonna use "as!" here and not feel bad about it because we're
            // already checking if it's set in main.swift
            let adminPassword = config["password"] as! String
            guard let postBody = request.body?.asURLEncodedMultiValue, let submittedPw = postBody["password"]?.first, submittedPw == adminPassword else {
                try response.send(status: .forbidden).end()
                next()
                return
            }
            guard let uuid = request.parameters["uuid"] else {
                try response.send(status: .notFound).end()
                next()
                return
            }
            do {
                let paste = try Paste.load(fromUuid: uuid)
                try paste.delete()
                try response.redirect("/")
            }
            catch {
                switch error {
                case Paste.PasteError.notFoundForUuid:
                    try response.send(status: .notFound).end()
                default:
                    try response.send(status: .internalServerError).end()
                }
            }
            next()
        }

        // Submit handler for new paste
        r.post("/new", middleware: BodyParserMultiValue())
        r.post("/new") { request, response, next in
            guard let postBody = request.body?.asURLEncodedMultiValue, let body = postBody["body"]?.first, let postedMode = postBody["mode"]?.first else {
                try response.send(status: .unprocessableEntity).end()
                next()
                return
            }

            guard let maxSize = config["max-size"] as? Int else {
                try response.send(status: .internalServerError).end()
                next()
                return
            }

            // Make sure the mode is legitimate
            var existsInModes = false
            for mode in modes {
                if mode["sysname"] == postedMode {
                    existsInModes = true
                    break
                }
            }

            guard existsInModes == true else {
                try response.send(status: .unprocessableEntity).end()
                next()
                return
            }

            let newPaste = Paste(raw: body, mode: postedMode)

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
                try response.send(status: .unprocessableEntity).end()
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
                    _ = response.send(status: .internalServerError)
                }
            }
            next()
        }

        return r
    }
}
