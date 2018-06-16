import XCTest
import Kitura
import KituraNet

import Wastebin

class WastebinTests: KituraTest {
    static var allTests = [
        ("testGetFrontPage", testGetFrontPage)
    ]

    private typealias BodyChecker =  (String) -> Void
    private func checkResponse(response: ClientResponse, expectedResponseText: String? = nil,
                               expectedStatusCode: HTTPStatusCode = HTTPStatusCode.OK, bodyChecker: BodyChecker? = nil) {
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

    func testGetFrontPage() {
        let bodyChecker: BodyChecker = { body in
            if body.contains("<textarea") == false {
                XCTFail("No textarea tag found on front page")
            }
        }
        runGetResponseTest(path: "/", bodyChecker: bodyChecker)
//        XCTFail("hello")
    }

}
