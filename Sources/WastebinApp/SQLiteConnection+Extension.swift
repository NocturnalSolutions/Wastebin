import Foundation
import Dispatch
import SwiftKuery
import SwiftKuerySQLite

extension SQLiteConnection {
    public func executeSync(query: Query, parameters: [String: Any?]? = nil) -> QueryResult {
        let semaphore = DispatchSemaphore(value: 0)
        var result: QueryResult? = nil
        DispatchQueue.global().async {
            if let parameters = parameters {
                self.execute(query: query, parameters: parameters) { queryResult in
                    result = queryResult
                    semaphore.signal()
                }
            }
            else {
                self.execute(query: query) { queryResult in
                    result = queryResult
                    semaphore.signal()
                }
            }
        }
        semaphore.wait()
        return result!
    }
}
