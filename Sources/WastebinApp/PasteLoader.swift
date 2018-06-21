import Foundation
import Kitura

class PasteLoader: RouterMiddleware {
    public func handle(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let uuid = request.parameters["uuid"], let paste = try? Paste.load(fromUuid: uuid) else {
            try response.send(status: .notFound).end()
            return
        }
        request.userInfo["loadedPaste"] = paste
        next()
    }
}
