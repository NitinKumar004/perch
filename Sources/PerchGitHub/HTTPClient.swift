import Foundation

/// A minimal HTTP surface, abstracted so the network can be faked in tests.
/// Every GitHub call goes through this, so no test ever touches the real API.
public struct HTTPRequest: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public let headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }
}

public protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// The real client, backed by `URLSession.shared`.
public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let http = response as? HTTPURLResponse

        var headers: [String: String] = [:]
        if let fields = http?.allHeaderFields {
            for (key, value) in fields {
                if let key = key as? String, let value = value as? String {
                    headers[key] = value
                }
            }
        }
        return HTTPResponse(status: http?.statusCode ?? 0, body: data, headers: headers)
    }
}
