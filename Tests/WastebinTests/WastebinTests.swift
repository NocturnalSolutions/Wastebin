import XCTest
import Kitura
import KituraNet
import Foundation

import WastebinApp

class WastebinTests: KituraTest {
    static var allTests = [
        ("testGetFrontPage", testGetFrontPage),
        ("testNewPost", testNewPost)
    ]

    let multipartBoundary = "----QuickAndDirty"
    let wastebin: WastebinApp = WastebinApp()

    private typealias BodyChecker =  (String) -> Void
    private typealias ResponseChecker = (ClientResponse) -> Void

    override func setUp() {
        let fileManager = FileManager.default
        //        let tempDir = fileManager.temporaryDirectory
        //        let dbFilePath = tempDir.appendingPathComponent("wastebin-test.sqlite")
        let dbFilePath = URL(fileURLWithPath: "/tmp/wastebin-test.sqlite")
        try? fileManager.removeItem(at: dbFilePath)

        wastebin.config["database-path"] = dbFilePath.absoluteString

        wastebin.connectDb()
        wastebin.installDb()
        let router = wastebin.generateRouter()
        Kitura.addHTTPServer(onPort: 8080, with: router)
        Kitura.start()
    }

    override func tearDown() {
        wastebin.disconnectDb()
        Kitura.stop()
    }

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

        var rawUrl: String? = nil

        let bc: BodyChecker = { body in
            XCTAssert(body.contains(post["body"]!), "Posted text not found on page")
            XCTAssert(body.contains("lang-\(post["mode"]!)"), "Posted mode not found on page")
            let viewRawPattern = "/[\\dA-F]{8}-[\\dA-F]{4}-[\\dA-F]{4}-[\\dA-F]{4}-[\\dA-F]{12}/raw"
            let regex = try! NSRegularExpression(pattern: viewRawPattern, options: [])
            let matches = regex.matches(in: body, options: [], range: NSRange(location: 0, length: body.count))
            if let match = matches.first {
                let nsRange = match.range(at: 0)
                if let range = Range(nsRange, in: body) {
                    rawUrl = String(body[range])
                }
            }
            XCTAssertNotNil(rawUrl, "Can't find link to raw representation on paste page")
        }

        runPostResponseTest(path: "/new", bodyChecker: bc, postBody: post)

        if let rawUrl = rawUrl {
            let rawBc: BodyChecker = {body in
                XCTAssert(body.contains(post["body"]!), "Posted text not found on raw path")
            }
            runGetResponseTest(path: rawUrl, bodyChecker: rawBc)
        }

    }

}
