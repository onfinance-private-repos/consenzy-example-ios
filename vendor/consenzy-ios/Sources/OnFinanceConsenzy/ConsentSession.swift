// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Client for the principal-facing (`/v1/me`) API of a Consenzy / Consent Data Master deployment.
///
/// Authentication uses **principal session tokens only** (`cps_…`): short-lived (at most one
/// hour), scoped to one customer, minted by the bank's own backend with
/// `POST /v1/principal-sessions` after it has authenticated the customer. The session provider
/// closure fetches such a token from that backend. Organisation API keys (`cdm_…`) are refused.
///
/// Behaviour:
/// * The token is cached and reused until the API answers 401, at which point it is discarded,
///   the provider is asked once for a fresh token, and the request is replayed once.
/// * GETs and the two POSTs that carry an `Idempotency-Key` (`giveConsent`, `fileDataRequest`)
///   are retried on transport errors, 5xx and 429, with exponential backoff and jitter, up to
///   `RetryPolicy.maxRetries` (default 3) retries. The same `Idempotency-Key` is sent on every
///   attempt, so the server records at most one consent / request.
/// * `acknowledgeBreachNotice` is idempotent on the server and is retried like a GET.
/// * Withdraw and logout are not retried automatically.
/// * Certificate pinning: pass a `URLSession` built with your pinning `URLSessionDelegate`
///   (see `ConsentSession.pinnedURLSession(delegate:)` and `PublicKeyPinningDelegate`).
public actor ConsentSession {
    public typealias SessionProvider = @Sendable () async throws -> String

    public struct RetryPolicy: Sendable, Hashable {
        /// Retries after the first attempt (so `maxRetries + 1` attempts in total).
        public var maxRetries: Int
        /// Backoff before retry *n* (0-based) is a random value in `0...min(maxDelay, baseDelay * 2^n)`.
        public var baseDelay: TimeInterval
        public var maxDelay: TimeInterval

        public init(maxRetries: Int = 3, baseDelay: TimeInterval = 0.5, maxDelay: TimeInterval = 8) {
            self.maxRetries = max(0, min(maxRetries, 3))
            self.baseDelay = max(0, baseDelay)
            self.maxDelay = max(0, maxDelay)
        }

        public static let `default` = RetryPolicy()
        public static let none = RetryPolicy(maxRetries: 0)
    }

    public let baseURL: URL
    public let retryPolicy: RetryPolicy

    private let sessionProvider: SessionProvider
    private let urlSession: URLSession
    private let decoder = JSONDecoder.consentDataMaster()
    private let encoder = JSONEncoder.consentDataMaster()
    private let userAgent: String

    private var cachedToken: String?
    private var pendingToken: Task<String, Error>?

    /// - Parameters:
    ///   - baseURL: The API root, e.g. `https://consent.bank.example`. Paths such as `/v1/me` are appended.
    ///   - sessionProvider: Returns a principal session token (`cps_…`) from your backend. Called on first
    ///     use and again after a 401. Concurrent calls are coalesced.
    ///   - urlSession: Inject a session configured with a pinning delegate in production.
    ///   - retryPolicy: Backoff for retryable requests.
    public init(
        baseURL: URL,
        sessionProvider: @escaping SessionProvider,
        urlSession: URLSession = .shared,
        retryPolicy: RetryPolicy = .default
    ) {
        self.baseURL = baseURL
        self.sessionProvider = sessionProvider
        self.urlSession = urlSession
        self.retryPolicy = retryPolicy
        self.userAgent = "consenzy-ios/\(ConsenzySDK.version)"
    }

    /// Builds an ephemeral `URLSession` (no cookie or cache persistence) whose TLS challenges are
    /// answered by `delegate`, e.g. a `PublicKeyPinningDelegate`.
    public static func pinnedURLSession(
        delegate: URLSessionDelegate,
        configuration: URLSessionConfiguration = .ephemeral
    ) -> URLSession {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Public API

    /// `GET /v1/me`
    public func me() async throws -> PrincipalProfile {
        try await send(Endpoint(method: "GET", path: "/v1/me"))
    }

    /// `GET /v1/me/notice`: the latest notice in `language` (or the principal's preferred
    /// language when nil), falling back to English server-side.
    public func currentNotice(language: Language? = nil) async throws -> Notice {
        var query: [URLQueryItem] = []
        if let language { query.append(URLQueryItem(name: "language", value: language.rawValue)) }
        return try await send(Endpoint(method: "GET", path: "/v1/me/notice", query: query))
    }

    /// `GET /v1/me/consents`, newest first.
    public func listConsents(activeOnly: Bool = false, limit: Int? = nil, offset: Int? = nil) async throws -> [Consent] {
        var query = [URLQueryItem(name: "active_only", value: activeOnly ? "true" : "false")]
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { query.append(URLQueryItem(name: "offset", value: String(offset))) }
        return try await send(Endpoint(method: "GET", path: "/v1/me/consents", query: query))
    }

    /// `POST /v1/me/consents` with `channel: "mobile_app"`. Call only after the customer's clear
    /// affirmative action (e.g. ticking each purpose). Returns one consent per purpose, in the
    /// order of `purposeIds`.
    ///
    /// - Parameter idempotencyKey: Defaults to a fresh UUID, reused across automatic retries. Pass
    ///   your own to make an app-level retry (e.g. after a crash) safe as well.
    public func giveConsent(
        noticeId: UUID,
        purposeIds: [UUID],
        expiresAt: Date? = nil,
        idempotencyKey: String? = nil
    ) async throws -> [Consent] {
        guard !purposeIds.isEmpty, purposeIds.count <= 20 else {
            throw ConsentClientError.invalidRequest("purpose_ids must contain between 1 and 20 purposes")
        }
        guard Set(purposeIds).count == purposeIds.count else {
            throw ConsentClientError.invalidRequest("purpose_ids contains duplicates")
        }
        let body = GrantBody(
            noticeId: noticeId.uuidString.lowercased(),
            purposeIds: purposeIds.map { $0.uuidString.lowercased() },
            channel: .mobileApp,
            expiresAt: expiresAt
        )
        return try await send(Endpoint(
            method: "POST", path: "/v1/me/consents", body: try encoder.encode(body),
            idempotencyKey: idempotencyKey ?? Self.newIdempotencyKey()
        ))
    }

    /// `POST /v1/me/consents/{id}/withdraw`. Not retried automatically.
    public func withdrawConsent(id: UUID, reason: String? = nil) async throws -> Consent {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, trimmed.count > 1000 {
            throw ConsentClientError.invalidRequest("reason must be at most 1000 characters")
        }
        let body = WithdrawBody(reason: (trimmed?.isEmpty ?? true) ? nil : trimmed)
        return try await send(Endpoint(
            method: "POST", path: "/v1/me/consents/\(id.uuidString.lowercased())/withdraw",
            body: try encoder.encode(body)
        ))
    }

    /// `GET /v1/me/data-requests`, newest first.
    public func listDataRequests(limit: Int? = nil, offset: Int? = nil) async throws -> [DataRequest] {
        var query: [URLQueryItem] = []
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { query.append(URLQueryItem(name: "offset", value: String(offset))) }
        return try await send(Endpoint(method: "GET", path: "/v1/me/data-requests", query: query))
    }

    /// `POST /v1/me/data-requests`. See `giveConsent` for `idempotencyKey`.
    public func fileDataRequest(_ submission: DataRequestSubmission, idempotencyKey: String? = nil) async throws -> DataRequest {
        try submission.validate()
        return try await send(Endpoint(
            method: "POST", path: "/v1/me/data-requests", body: try encoder.encode(DataRequestBody(submission: submission)),
            idempotencyKey: idempotencyKey ?? Self.newIdempotencyKey()
        ))
    }

    /// `GET /v1/me/breach-notices`: personal data breach intimations sent to this principal
    /// (DPDP Rules r.7(1)), newest first. Every session can read them, like the profile.
    public func listBreachNotices(limit: Int? = nil, offset: Int? = nil) async throws -> [BreachNotice] {
        var query: [URLQueryItem] = []
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { query.append(URLQueryItem(name: "offset", value: String(offset))) }
        let notices: [BreachNotice] = try await send(Endpoint(method: "GET", path: "/v1/me/breach-notices", query: query))
        return notices.sortedNewestFirst()
    }

    /// `POST /v1/me/breach-notices/{breach_id}/acknowledge`: records that the principal has read
    /// the notice ("I have read this"). Idempotent on the server (the first acknowledgement time
    /// is kept), so it is retried like a GET and is safe to call again.
    public func acknowledgeBreachNotice(breachId: UUID) async throws -> BreachNotice {
        try await send(Endpoint(
            method: "POST", path: "/v1/me/breach-notices/\(breachId.uuidString.lowercased())/acknowledge",
            idempotent: true
        ))
    }

    /// As `acknowledgeBreachNotice(breachId: UUID)`, for an id held as a string. Anything that is
    /// not a UUID throws `ConsentClientError.invalidRequest` before any network call.
    public func acknowledgeBreachNotice(breachId: String) async throws -> BreachNotice {
        guard let id = UUID(uuidString: breachId) else {
            throw ConsentClientError.invalidRequest("breachId must be a UUID")
        }
        return try await acknowledgeBreachNotice(breachId: id)
    }

    /// `POST /v1/me/logout`: revokes the current session token server-side and forgets it locally.
    /// A no-op when no token has been fetched yet.
    public func logout() async throws {
        guard cachedToken != nil else { return }
        defer { invalidateToken() }
        let _: Empty = try await send(Endpoint(method: "POST", path: "/v1/me/logout"), allowRefresh: false)
    }

    /// Drops the cached token so the next call asks the provider again (e.g. on account switch).
    public func invalidateToken() {
        cachedToken = nil
        pendingToken?.cancel()
        pendingToken = nil
    }

    // MARK: - Transport

    struct Endpoint {
        var method: String
        var path: String
        var query: [URLQueryItem] = []
        var body: Data?
        var idempotencyKey: String?
        /// The server treats repeats as no-ops, so it is safe to retry without a key.
        var idempotent = false

        var isRetryable: Bool { method == "GET" || idempotencyKey != nil || idempotent }
    }

    private struct Empty: Decodable {}

    private struct GrantBody: Encodable {
        let noticeId: String
        let purposeIds: [String]
        let channel: Channel
        let expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case channel
            case noticeId = "notice_id"
            case purposeIds = "purpose_ids"
            case expiresAt = "expires_at"
        }
    }

    private struct WithdrawBody: Encodable {
        let reason: String?
    }

    static func newIdempotencyKey() -> String { UUID().uuidString.lowercased() }

    /// Validates a token from the provider: principal session tokens only.
    static func validate(token raw: String) throws -> String {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("cdm_") { throw ConsentClientError.organizationAPIKeyRejected }
        guard token.hasPrefix("cps_"), token.count > 4, token.count <= 128,
              token.unicodeScalars.allSatisfy({ $0.value > 32 && $0.value < 127 })
        else { throw ConsentClientError.invalidSessionToken }
        return token
    }

    private func token() async throws -> String {
        if let cachedToken { return cachedToken }
        if let pendingToken { return try await pendingToken.value }
        let provider = sessionProvider
        let task = Task { try Self.validate(token: try await provider()) }
        pendingToken = task
        do {
            let token = try await task.value
            if pendingToken == task {
                cachedToken = token
                pendingToken = nil
            }
            return token
        } catch {
            if pendingToken == task { pendingToken = nil }
            throw error
        }
    }

    private func send<T: Decodable>(_ endpoint: Endpoint, allowRefresh: Bool = true) async throws -> T {
        var refreshed = !allowRefresh
        var attempt = 0
        while true {
            try Task.checkCancellation()
            let token = try await token()
            let request = try makeRequest(endpoint, token: token)
            let outcome: (Data, HTTPURLResponse)
            do {
                outcome = try await perform(request)
            } catch let error as URLError where error.code != .cancelled && endpoint.isRetryable && attempt < retryPolicy.maxRetries {
                try await backoff(attempt: attempt, retryAfter: nil)
                attempt += 1
                continue
            } catch let error as URLError {
                if error.code == .cancelled && Task.isCancelled { throw CancellationError() }
                throw ConsentClientError.transport(code: error.code.rawValue, message: error.localizedDescription)
            }
            let (data, response) = outcome

            switch response.statusCode {
            case 200..<300:
                if T.self == Empty.self { return Empty() as! T }
                do {
                    return try decoder.decode(T.self, from: data)
                } catch {
                    throw ConsentClientError.decoding(String(describing: error))
                }
            case 401 where !refreshed:
                refreshed = true
                if cachedToken == token { cachedToken = nil }
                continue
            case 429, 500..<600:
                if endpoint.isRetryable && attempt < retryPolicy.maxRetries {
                    try await backoff(attempt: attempt, retryAfter: Self.retryAfter(response))
                    attempt += 1
                    continue
                }
                fallthrough
            default:
                if response.statusCode == 401 && cachedToken == token { cachedToken = nil }
                throw ConsentAPIError(status: response.statusCode, detail: ErrorDetail.decode(from: data), body: data)
            }
        }
    }

    private func makeRequest(_ endpoint: Endpoint, token: String) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ConsentClientError.invalidRequest("invalid base URL")
        }
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + endpoint.path
        components.queryItems = endpoint.query.isEmpty ? nil : endpoint.query
        guard let url = components.url else { throw ConsentClientError.invalidRequest("invalid URL") }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let body = endpoint.body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key = endpoint.idempotencyKey {
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        return request
    }

    /// `dataTask` + continuation rather than `URLSession.data(for:)`, which is not available on
    /// every Linux Foundation release.
    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let session = urlSession
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        let ns = error as NSError
                        let urlError = (error as? URLError)
                            ?? (ns.domain == NSURLErrorDomain
                                ? URLError(urlErrorCode(ns.code), userInfo: ns.userInfo)
                                : URLError(.unknown, userInfo: [NSUnderlyingErrorKey: error]))
                        continuation.resume(throwing: urlError)
                    } else if let http = response as? HTTPURLResponse {
                        continuation.resume(returning: (data ?? Data(), http))
                    } else {
                        continuation.resume(throwing: ConsentClientError.invalidResponse)
                    }
                }
                box.set(task)
                task.resume()
            }
        } onCancel: {
            box.cancel()
        }
    }

    private func backoff(attempt: Int, retryAfter: TimeInterval?) async throws {
        let ceiling = min(retryPolicy.maxDelay, retryPolicy.baseDelay * pow(2, Double(attempt)))
        var delay = ceiling > 0 ? Double.random(in: 0...ceiling) : 0
        if let retryAfter { delay = max(delay, min(retryAfter, retryPolicy.maxDelay)) }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }

    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)), seconds >= 0
        else { return nil }
        return seconds
    }
}

/// `URLError.Code(rawValue:)` is failable on Linux Foundation and non-failable on Apple platforms.
private func urlErrorCode(_ raw: Int) -> URLError.Code {
    #if canImport(FoundationNetworking)
    return URLError.Code(rawValue: raw) ?? .unknown
    #else
    return URLError.Code(rawValue: raw)
    #endif
}

/// Holds a `URLSessionDataTask` for cancellation from another thread.
private final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    func set(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let cancelNow = cancelled
        lock.unlock()
        if cancelNow { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}

public enum ConsenzySDK {
    public static let version = "0.1.0"
}
