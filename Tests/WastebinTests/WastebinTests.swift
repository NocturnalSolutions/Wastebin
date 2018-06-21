import XCTest
import Kitura
import KituraNet

import Wastebin

class WastebinTests: KituraTest {
    static var allTests = [
        ("testGetFrontPage", testGetFrontPage),
        ("testNewPost", testNewPost)
    ]

    let multipartBoundary = "----QuickAndDirty"

    private typealias BodyChecker =  (String) -> Void
    private typealias ResponseChecker = (ClientResponse) -> Void
    private func checkResponse(response: ClientResponse, expectedResponseText: String? = nil,
                               expectedStatusCode: HTTPStatusCode = HTTPStatusCode.OK, bodyChecker: BodyChecker? = nil, responseChecker: ResponseChecker? = nil) {
        XCTAssertEqual(response.statusCode, expectedStatusCode,
                       "No success status code returned")
        if let optionalBody = try? response.readString(), let body = optionalBody {
            if let expectedResponseText = expectedResponseText {
                XCTAssertEqual(body, expectedResponseText, "mismatch in body")
            }
            bodyChecker?(body)
        } else {
            XCTFail("No response body")
        }
        responseChecker?(response)
    }

    private func runGetResponseTest(path: String, expectedResponseText: String? = nil,
                                    expectedStatusCode: HTTPStatusCode = HTTPStatusCode.OK,
                                    bodyChecker: BodyChecker? = nil) {
        performServerTest { expectation in
            self.performRequest("get", path: path, expectation: expectation) { response in
                self.checkResponse(response: response, expectedResponseText: expectedResponseText,
                                   expectedStatusCode: expectedStatusCode, bodyChecker: bodyChecker)
                expectation.fulfill()
            }
        }
    }

    private func runPostResponseTest(path: String, expectedResponseText: String? = nil,
                                     expectedStatusCode: HTTPStatusCode = HTTPStatusCode.OK,
                                     bodyChecker: BodyChecker? = nil, responseChecker: ResponseChecker? = nil, postBody: [String: String]) {
        performServerTest { expectation in
            let rm: RequestModifier = { req in
                // Add headers for the form data and write the request body
                req.headers["Content-Type"] = "multipart/form-data; boundary=" + self.multipartBoundary
                req.write(from: self.mimeEncode(postBody))
            }
            self.performRequest("post", path: path, expectation: expectation, requestModifier: rm) { response in
                self.checkResponse(response: response, expectedResponseText: expectedResponseText, expectedStatusCode: expectedStatusCode, bodyChecker: bodyChecker, responseChecker: responseChecker)
                expectation.fulfill()
            }
        }
    }

    private func mimeEncode(_ values: [String: String]) -> String {
        let rn = "\r\n"
        var body = "--" + self.multipartBoundary
        for (fieldName, value) in values {
            body += rn + "Content-Disposition: form-data; name=\"\(fieldName)\"" + rn
            body += "Content-Type: text/plain" + rn + rn
            body += value + rn
            body += "--" + self.multipartBoundary
        }
        return body + "--"
    }

    func testGetFrontPage() {
        let bodyChecker: BodyChecker = { body in
            if body.contains("<textarea") == false {
                XCTFail("No textarea tag found on front page")
            }
        }
        runGetResponseTest(path: "/", bodyChecker: bodyChecker)
    }

    func testNewPost() {
        let post = [
            "body": "The quick brown fox jumps over the lazy dog.",
            "mode": "_plain_",
        ]

        let bc: BodyChecker = { body in
            XCTAssert(body.contains(post["body"]!), "Posted text not found on page")
            XCTAssert(body.contains("lang-\(post["mode"]!)"), "Posted mode not found on page")
        }

        runPostResponseTest(path: "/new", bodyChecker: bc, postBody: post)
    }

}
