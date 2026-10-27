// DEMO ONLY. Nothing in App/Demo is needed in a real app: delete the folder and point the app at your own backend.
//
// A fake HTTP transport. `DemoBackend.makeURLSession()` registers this class on a `URLSessionConfiguration`; the app
// hands that `URLSession` to its session-server client and, as `urlSession:`, to `ConsentSession`. Every request to a
// demo host (`https://demo-….consenzy.invalid`) is answered in memory by the matching `DemoBackend`, so the SDK's real
// request building, token handling, retries, idempotency keys and error decoding all run unchanged.

import Foundation

final class DemoURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var backends: [String: DemoBackend] = [:]

    static func register(_ backend: DemoBackend) {
        lock.lock()
        defer { lock.unlock() }
        if let host = backend.baseURL.host { backends[host] = backend }
    }

    private static func backend(for url: URL?) -> DemoBackend? {
        guard let host = url?.host else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return backends[host]
    }

    override class func canInit(with request: URLRequest) -> Bool { backend(for: request.url) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let backend = Self.backend(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let answer = backend.handle(
            method: request.httpMethod ?? "GET",
            url: url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.readBody(request)
        )
        var headers = ["Content-Type": "application/json"]
        if answer.status == 401 { headers["WWW-Authenticate"] = "Bearer" }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !answer.body.isEmpty { client?.urlProtocol(self, didLoad: answer.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `URLSession` hands a custom protocol the body as a stream, not as `httpBody`.
    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
