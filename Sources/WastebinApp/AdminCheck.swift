import Foundation
import Kitura

class AdminCheck: RouterMiddleware {
    let adminPass: String
    init(adminPass: String) {
        self.adminPass = adminPass
    }
    func handle(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
        guard let postBody = request.body?.asURLEncodedMultiValue, let submittedPw = postBody["password"]?.first, submittedPw == adminPass else {
            try response.send(status: .forbidden).end()
            return
        }
        next()
    }
}
