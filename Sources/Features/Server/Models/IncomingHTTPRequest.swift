import Foundation

struct IncomingHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}
