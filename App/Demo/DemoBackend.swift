// DEMO ONLY. Nothing in App/Demo is needed in a real app: delete the folder and point the app at your own backend.
//
// An in-memory stand-in for two servers, answered over a fake HTTP transport (`DemoURLProtocol`) so the app and the
// real Consenzy SDK run exactly the code paths they run against real servers:
//
//   1. The example session server (https://github.com/never2average/consenzy-example-session-server):
//        GET  /demo-customers, POST /session, POST /consent-check
//      In a real deployment this is YOUR backend: it holds the org API key and mints `cps_…` session tokens.
//   2. The Consenzy principal API that the SDK calls with those tokens: /v1/me/*
//
// It is a Swift port of the session server's `src/mock.js` and uses the same synthetic fixtures: notice in en/hi with
// English fallback, grant with supersede and Idempotency-Key replay, withdraw, rights requests with validation and
// time-based status progression, the DPDP s.9 guardian rule, session capabilities and logout.

import CryptoKit
import Foundation
import OnFinanceConsenzy

struct DemoHTTPResponse {
    let status: Int
    let body: Data
}

final class DemoBackend: @unchecked Sendable {
    static let allCapabilities = ["consents:write", "requests:read", "requests:write"]
    static let requestTypes = ["access", "correction", "completion", "updating", "erasure", "grievance", "nomination"]
    static let guardianRequired =
        "this principal acts through a guardian: the session must be minted with acting_as=guardian (s.9)"

    /// The app-wide demo backend. Its state lives until the app is killed, like the session server's memory.
    static let shared = DemoBackend()

    /// A fake host that only `DemoURLProtocol` answers. `.invalid` never resolves on a real network.
    let baseURL: URL
    let fixtures: DemoFixtures

    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var sessions: [String: DemoSession] = [:]
    private var consents: [DemoConsentRow] = []
    private var requests: [DemoRequestRow] = []
    private var idempotency: [String: DemoHTTPResponse] = [:]
    private var ledgerSequence = 0
    private let encoder = JSONEncoder.consentDataMaster()

    /// - Parameter now: The clock. Tests pass their own to move rights requests through their statuses.
    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
        self.fixtures = DemoFixtures.load()
        let host = "demo-\(UUID().uuidString.prefix(8).lowercased()).consenzy.invalid"
        self.baseURL = URL(string: "https://\(host)")!
        let start = now()
        for seed in fixtures.seedDataRequests {
            guard let principal = principal(ref: seed.externalRef) else { continue }
            let received = start.addingTimeInterval(-seed.receivedDaysAgo * 86_400)
            requests.append(DemoRequestRow(
                principal: principal, type: seed.requestType, details: seed.details, channel: seed.channel,
                channelReference: seed.channelReference, received: received, slaDays: fixtures.requestSlaDays,
                id: seed.id, fixedStatus: seed.status
            ))
        }
        DemoURLProtocol.register(self)
    }

    /// A `URLSession` whose requests to `baseURL` are answered by this backend. The app passes it to its session-server
    /// client and, as `urlSession:`, to `ConsentSession`, so the SDK's own networking code runs unchanged.
    func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemoURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: - Routing

    func handle(method: String, url: URL, headers: [String: String], body: Data) -> DemoHTTPResponse {
        lock.lock()
        defer { lock.unlock() }
        let path = url.path.isEmpty ? "/" : url.path
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        switch (method, path) {
        case ("GET", "/healthz"):
            return json(["ok": true, "mode": "demo"])
        case ("GET", "/demo-customers"):
            return json(array: fixtures.principals.map { p -> [String: Any] in
                ["external_ref": p.externalRef, "label": p.label, "acts_through_guardian": p.actsThroughGuardian]
            })
        case ("POST", "/session"):
            return mintRoute(body)
        case ("POST", "/consent-check"):
            return checkRoute(body)
        default:
            break
        }
        guard path == "/v1/me" || path.hasPrefix("/v1/me/") else { return detail(404, "not found") }

        // Principal API: authenticated with the cps_ tokens minted above.
        let auth = header("Authorization") ?? ""
        guard auth.hasPrefix("Bearer cps_"), let session = activeSession(String(auth.dropFirst("Bearer ".count))) else {
            return detail(401, "invalid or expired session token")
        }
        let parts = path.split(separator: "/").map(String.init) // ["v1", "me", ...]
        let rest = Array(parts.dropFirst(2))
        let (limit, offset) = page(query)

        switch (method, rest) {
        case ("GET", []):
            return json(me(session))
        case ("GET", ["notice"]):
            return encoded(200, notice(language: query["language"] ?? session.principal.preferredLanguage))
        case ("GET", ["consents"]):
            let activeOnly = (query["active_only"] ?? "false") == "true"
            return encoded(200, Array(listConsents(session, activeOnly: activeOnly).dropFirst(offset).prefix(limit)))
        case ("POST", ["consents"]):
            return idempotent(session, "consents", header("Idempotency-Key")) { grant(session, body) }
        case ("POST", let r) where r.count == 3 && r[0] == "consents" && r[2] == "withdraw":
            return withdraw(session, consentId: r[1], body: body)
        case ("GET", ["data-requests"]):
            guard session.capabilities.contains("requests:read") else { return lacks("requests:read") }
            return encoded(200, Array(listRequests(session).dropFirst(offset).prefix(limit)))
        case ("POST", ["data-requests"]):
            return idempotent(session, "data-requests", header("Idempotency-Key")) { fileRequest(session, body) }
        case ("GET", ["breach-notices"]):
            return json(array: [])
        case ("POST", let r) where r.count == 3 && r[0] == "breach-notices" && r[2] == "acknowledge":
            return detail(404, "breach notice not found")
        case ("POST", ["logout"]):
            sessions[session.token]?.revoked = true
            return DemoHTTPResponse(status: 204, body: Data())
        default:
            return detail(404, "not found")
        }
    }

    // MARK: - Session server contract (POST /session, POST /consent-check)

    private func mintRoute(_ body: Data) -> DemoHTTPResponse {
        let input = object(body)
        guard let ref = input["external_ref"] as? String, principal(ref: ref) != nil else {
            return detail(403, "unknown customer")
        }
        let actingAs = (input["acting_as"] as? String) ?? "data_principal"
        guard ["data_principal", "guardian"].contains(actingAs) else {
            return detail(422, "acting_as must be data_principal or guardian")
        }
        return mint(externalRef: ref, actingAs: actingAs)
    }

    /// What `POST /v1/principal-sessions` does on the real server (the session server calls it with its org key).
    private func mint(externalRef: String, actingAs: String, ttlSeconds: TimeInterval = 900) -> DemoHTTPResponse {
        guard let principal = principal(ref: externalRef) else { return detail(404, "principal not found") }
        if actingAs == "guardian" && !principal.actsThroughGuardian {
            return detail(422, "principal does not act through a guardian")
        }
        let token = "cps_demo_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let session = DemoSession(
            token: token, sessionId: UUID().uuidString.lowercased(), principal: principal,
            expiresAt: now().addingTimeInterval(ttlSeconds), actingAs: actingAs,
            capabilities: Self.allCapabilities.sorted()
        )
        sessions[token] = session
        return json([
            "token": token,
            "session_id": session.sessionId,
            "principal_id": principal.principalId,
            "expires_at": ISO8601.format(session.expiresAt),
            "acting_as": actingAs,
            "capabilities": session.capabilities,
            "application_id": NSNull(),
            "base_url": baseURL.absoluteString,
            "mode": "demo",
        ])
    }

    /// What `POST /v1/consents/check` does on the real server: is there an active consent for this purpose?
    private func checkRoute(_ body: Data) -> DemoHTTPResponse {
        let input = object(body)
        guard let ref = input["external_ref"] as? String, principal(ref: ref) != nil else {
            return detail(403, "unknown customer")
        }
        guard let purposeCode = input["purpose_code"] as? String, !purposeCode.isEmpty else {
            return detail(422, "purpose_code is required")
        }
        guard let consent = consents.first(where: { $0.externalRef == ref && $0.purposeCode == purposeCode && $0.status == "active" })
        else {
            return json([
                "allowed": false, "basis": NSNull(), "consent_id": NSNull(), "expires_at": NSNull(),
                "ledger_event_id": NSNull(), "ledger_hash": NSNull(),
            ])
        }
        return json([
            "allowed": true,
            "basis": "consent",
            "consent_id": consent.id,
            "expires_at": consent.expiresAt.map { ISO8601.format($0) as Any } ?? NSNull(),
            "ledger_event_id": consent.ledgerEventId,
            "ledger_hash": consent.ledgerHash,
        ])
    }

    // MARK: - Principal API (/v1/me)

    private func me(_ s: DemoSession) -> [String: Any] {
        [
            "principal_id": s.principal.principalId,
            "external_ref": s.principal.externalRef,
            "preferred_language": s.principal.preferredLanguage,
            "acts_through_guardian": s.principal.actsThroughGuardian,
            "guardian_verified": s.principal.guardianVerified,
            "acting_as": s.actingAs,
            "capabilities": s.capabilities,
        ]
    }

    /// The notice in `language`, or in English when the bank has not published that language.
    private func notice(language: String) -> Notice {
        let translations = fixtures.notice.translations
        let lang = translations[language] != nil ? language : "en"
        let tr = translations[lang]!
        return Notice(
            id: UUID(uuidString: fixtures.notice.id)!,
            version: fixtures.notice.version,
            language: Language(rawValue: lang),
            title: tr.title,
            body: tr.body,
            purposes: fixtures.purposes.map { p in
                NoticePurpose(
                    id: UUID(uuidString: p.id)!, code: p.code, name: tr.purposes[p.code]?.name ?? p.code,
                    description: tr.purposes[p.code]?.description ?? "", dataCategories: p.dataCategories,
                    retentionDays: p.retentionDays
                )
            }
        )
    }

    private func listConsents(_ s: DemoSession, activeOnly: Bool) -> [DemoConsentRow] {
        consents.enumerated()
            .filter { $0.element.externalRef == s.principal.externalRef && (!activeOnly || $0.element.status == "active") }
            .sorted { $0.element.createdAt != $1.element.createdAt ? $0.element.createdAt > $1.element.createdAt : $0.offset < $1.offset }
            .map(\.element)
    }

    private func grant(_ s: DemoSession, _ body: Data) -> DemoHTTPResponse {
        guard s.capabilities.contains("consents:write") else { return lacks("consents:write") }
        if s.principal.actsThroughGuardian && s.actingAs != "guardian" { return detail(422, Self.guardianRequired) }
        let input = object(body)
        guard (input["notice_id"] as? String) == fixtures.notice.id else { return detail(404, "notice not found") }
        guard let ids = input["purpose_ids"] as? [String], !ids.isEmpty else {
            return validation(["body", "purpose_ids"], "List should have at least 1 item", type: "too_short")
        }
        let purposes = ids.map { id in fixtures.purposes.first { $0.id == id } }
        guard purposes.allSatisfy({ $0 != nil }) else { return detail(422, "purpose not in notice") }
        let t = now()
        let expiresAt = (input["expires_at"] as? String).flatMap(ISO8601.parse)
        var out: [DemoConsentRow] = []
        for purpose in purposes.compactMap({ $0 }) {
            for i in consents.indices
            where consents[i].externalRef == s.principal.externalRef && consents[i].purposeCode == purpose.code && consents[i].status == "active" {
                consents[i].status = "superseded"
                consents[i].updatedAt = t
            }
            let id = UUID().uuidString.lowercased()
            ledgerSequence += 1
            let hash = SHA256.hash(data: Data("\(id):\(Int(t.timeIntervalSince1970 * 1000))".utf8))
            let row = DemoConsentRow(
                id: id, principalId: s.principal.principalId, purposeId: purpose.id, purposeCode: purpose.code,
                noticeId: fixtures.notice.id, status: "active", channel: (input["channel"] as? String) ?? "mobile_app",
                givenAt: t, expiresAt: expiresAt, createdAt: t, updatedAt: t,
                externalRef: s.principal.externalRef, ledgerEventId: ledgerSequence,
                ledgerHash: hash.map { String(format: "%02x", $0) }.joined()
            )
            consents.append(row)
            out.append(row)
        }
        return encoded(201, out)
    }

    private func withdraw(_ s: DemoSession, consentId: String, body: Data) -> DemoHTTPResponse {
        guard s.capabilities.contains("consents:write") else { return lacks("consents:write") }
        guard let i = consents.firstIndex(where: { $0.id == consentId.lowercased() && $0.externalRef == s.principal.externalRef }) else {
            return detail(404, "consent not found")
        }
        guard consents[i].status == "active" else { return detail(409, "consent is not active") }
        let t = now()
        consents[i].status = "withdrawn"
        consents[i].withdrawnAt = t
        consents[i].withdrawalReason = object(body)["reason"] as? String
        consents[i].updatedAt = t
        return encoded(200, consents[i])
    }

    private func listRequests(_ s: DemoSession) -> [DemoRequestRow] {
        for i in requests.indices where requests[i].externalRef == s.principal.externalRef {
            progress(&requests[i])
        }
        return requests
            .filter { $0.externalRef == s.principal.externalRef }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    /// Demo requests move on by themselves so the status-tracking screen has something to show.
    private func progress(_ row: inout DemoRequestRow) {
        guard row.fixedStatus == nil else { return }
        let age = now().timeIntervalSince(row.receivedAt)
        let steps = fixtures.statusProgressionSeconds
        if age >= steps.completed {
            let closed = row.receivedAt.addingTimeInterval(steps.completed)
            row.status = "completed"
            row.closedAt = row.closedAt ?? closed
            row.response = row.response ?? ["summary": .string("Demo: your \(row.requestType) request was completed.")]
            row.updatedAt = row.closedAt ?? closed
        } else if age >= steps.inProgress {
            row.status = "in_progress"
            row.updatedAt = row.receivedAt.addingTimeInterval(steps.inProgress)
        }
    }

    private struct FileBody: Decodable {
        let requestType: String?
        let details: [String: JSONValue]?
        let channel: String?

        enum CodingKeys: String, CodingKey {
            case details, channel
            case requestType = "request_type"
        }
    }

    private func fileRequest(_ s: DemoSession, _ body: Data) -> DemoHTTPResponse {
        guard s.capabilities.contains("requests:write") else { return lacks("requests:write") }
        guard let input = try? JSONDecoder().decode(FileBody.self, from: body),
              let type = input.requestType, Self.requestTypes.contains(type)
        else {
            return validation(["body", "request_type"], "Input should be \(Self.requestTypes.joined(separator: ", "))", type: "literal_error")
        }
        let details = input.details ?? [:]
        if let problem = Self.validateDetails(type: type, details) {
            return validation(["body", "details", problem.field], problem.msg, type: "value_error")
        }
        if type == "grievance", let related = details["related_request_id"]?.stringValue,
           !requests.contains(where: { $0.id == related.lowercased() && $0.externalRef == s.principal.externalRef }) {
            return detail(404, "related data request not found")
        }
        let row = DemoRequestRow(
            principal: s.principal, type: type, details: details, channel: input.channel ?? "app",
            channelReference: nil, received: now(), slaDays: fixtures.requestSlaDays
        )
        requests.append(row)
        return encoded(201, row)
    }

    /// The server's per-type details rules (`DETAILS_BY_TYPE`), as the mock implements them.
    static func validateDetails(type: String, _ d: [String: JSONValue]) -> (field: String, msg: String)? {
        func short(_ v: JSONValue?) -> Bool {
            switch v {
            case nil, .some(.null): return true
            case .some(.string(let s)): return s.count <= 500
            default: return false
            }
        }
        func present(_ v: JSONValue?) -> Bool {
            if case .string(let s)? = v { return !s.isEmpty }
            return false
        }
        switch type {
        case "access":
            return short(d["note"]) ? nil : ("note", "String should have at most 500 characters")
        case "correction", "completion", "updating":
            guard case .object(let fields)? = d["fields"], !fields.isEmpty else {
                return ("fields", "Dictionary should have at least 1 item")
            }
            let pattern = "^[a-z][a-z0-9_]{0,63}$"
            if let bad = fields.keys.first(where: { $0.range(of: pattern, options: .regularExpression) == nil }) {
                return ("fields", "invalid field name: \(bad)")
            }
            return nil
        case "erasure":
            return short(d["reason"]) ? nil : ("reason", "String should have at most 500 characters")
        case "grievance":
            guard case .string(let description)? = d["description"],
                  !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return ("description", "Field required") }
            switch d["related_request_id"] {
            case nil, .some(.null): return nil
            case .some(.string(let id)) where UUID(uuidString: id) != nil: return nil
            default: return ("related_request_id", "Input should be a valid UUID")
            }
        case "nomination":
            if !present(d["nominee_name"]) { return ("nominee_name", "Field required") }
            if !present(d["relationship"]) { return ("relationship", "Field required") }
            if !present(d["nominee_email"]) && !present(d["nominee_phone"]) {
                return ("nominee_email", "nominee_email or nominee_phone is required")
            }
            return nil
        default:
            return nil
        }
    }

    /// The same Idempotency-Key from the same principal replays the first successful answer instead of recording twice.
    private func idempotent(_ s: DemoSession, _ endpoint: String, _ key: String?, _ run: () -> DemoHTTPResponse) -> DemoHTTPResponse {
        guard let key, !key.isEmpty else { return run() }
        let k = "\(s.principal.principalId):\(endpoint):\(key)"
        if let replay = idempotency[k] { return replay }
        let response = run()
        if response.status < 300 { idempotency[k] = response }
        return response
    }

    // MARK: - Helpers

    private func principal(ref: String) -> DemoFixtures.Principal? {
        fixtures.principals.first { $0.externalRef == ref }
    }

    private func activeSession(_ token: String) -> DemoSession? {
        guard let s = sessions[token], !s.revoked, s.expiresAt > now() else { return nil }
        return s
    }

    private func page(_ query: [String: String]) -> (Int, Int) {
        let limit = min(max(Int(query["limit"] ?? "") ?? 50, 1), 200)
        let offset = max(Int(query["offset"] ?? "") ?? 0, 0)
        return (limit, offset)
    }

    private func object(_ body: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }

    private func json(_ value: [String: Any], status: Int = 200) -> DemoHTTPResponse {
        DemoHTTPResponse(status: status, body: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data())
    }

    private func json(array value: [Any], status: Int = 200) -> DemoHTTPResponse {
        DemoHTTPResponse(status: status, body: (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data())
    }

    private func encoded<T: Encodable>(_ status: Int, _ value: T) -> DemoHTTPResponse {
        DemoHTTPResponse(status: status, body: (try? encoder.encode(value)) ?? Data())
    }

    private func detail(_ status: Int, _ message: String) -> DemoHTTPResponse {
        json(["detail": message], status: status)
    }

    /// 403 in the real API's wording, so the SDK's `ConsentAPIError.missingCapability` recognises it.
    private func lacks(_ capability: String) -> DemoHTTPResponse {
        detail(403, "session lacks capability \(capability)")
    }

    private func validation(_ loc: [String], _ msg: String, type: String) -> DemoHTTPResponse {
        let issue: [String: Any] = ["loc": loc, "msg": msg, "type": type]
        return json(["detail": [issue]], status: 422)
    }
}

// MARK: - Rows

private struct DemoSession {
    let token: String
    let sessionId: String
    let principal: DemoFixtures.Principal
    let expiresAt: Date
    let actingAs: String
    let capabilities: [String]
    var revoked = false
}

/// A consent as `/v1/me/consents` returns it, plus demo-only bookkeeping that is not encoded.
private struct DemoConsentRow: Encodable {
    let id: String
    let principalId: String
    let purposeId: String
    let purposeCode: String
    let noticeId: String
    var status: String
    let channel: String
    var consentManagerRef: String?
    let givenAt: Date
    let expiresAt: Date?
    var withdrawnAt: Date?
    var withdrawalReason: String?
    let createdAt: Date
    var updatedAt: Date

    let externalRef: String
    let ledgerEventId: Int
    let ledgerHash: String

    enum CodingKeys: String, CodingKey {
        case id, status, channel
        case principalId = "principal_id"
        case purposeId = "purpose_id"
        case purposeCode = "purpose_code"
        case noticeId = "notice_id"
        case consentManagerRef = "consent_manager_ref"
        case givenAt = "given_at"
        case expiresAt = "expires_at"
        case withdrawnAt = "withdrawn_at"
        case withdrawalReason = "withdrawal_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A rights request as `/v1/me/data-requests` returns it, plus demo-only bookkeeping that is not encoded.
private struct DemoRequestRow: Encodable {
    let id: String
    let principalId: String
    let requestType: String
    var status: String
    let channel: String
    let channelReference: String?
    let details: [String: JSONValue]
    var response: [String: JSONValue]?
    let assignedTo: String? = nil
    let dueAt: Date
    let receivedAt: Date
    var closedAt: Date?
    let createdAt: Date
    var updatedAt: Date

    let externalRef: String
    /// Seeded requests keep their status; new ones progress received → in_progress → completed.
    let fixedStatus: String?

    init(
        principal: DemoFixtures.Principal, type: String, details: [String: JSONValue], channel: String,
        channelReference: String?, received: Date, slaDays: Int, id: String = UUID().uuidString.lowercased(),
        fixedStatus: String? = nil
    ) {
        self.id = id
        self.principalId = principal.principalId
        self.requestType = type
        self.status = fixedStatus ?? "received"
        self.channel = channel
        self.channelReference = channelReference
        self.details = details
        self.dueAt = received.addingTimeInterval(TimeInterval(slaDays) * 86_400)
        self.receivedAt = received
        self.createdAt = received
        self.updatedAt = received
        self.externalRef = principal.externalRef
        self.fixedStatus = fixedStatus
    }

    enum CodingKeys: String, CodingKey {
        case id, status, channel, details, response
        case principalId = "principal_id"
        case requestType = "request_type"
        case channelReference = "channel_reference"
        case assignedTo = "assigned_to"
        case dueAt = "due_at"
        case receivedAt = "received_at"
        case closedAt = "closed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
