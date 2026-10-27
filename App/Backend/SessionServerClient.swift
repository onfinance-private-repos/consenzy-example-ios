// The app's client for ITS OWN backend: the example session server
// (https://github.com/never2average/consenzy-example-session-server), or the in-app demo that answers the same contract.
//
// Your backend does the two things an app must never do itself, because both need the organisation API key (`cdm_…`):
//   POST /session        mint a short-lived principal session token (`cps_…`) for the signed-in customer
//   POST /consent-check  ask the consent ledger whether a purpose is allowed before processing data for it
// The app never sees the org key; it only ever receives `cps_…` tokens.

import Foundation
import OnFinanceConsenzy

/// `POST /session` response: a principal session token plus the base URL to give the SDK.
struct SessionGrant: Decodable, Equatable, Sendable {
    let token: String
    let baseURL: String
    let principalId: String
    let actingAs: String
    let capabilities: [String]
    let expiresAt: String
    let mode: String

    enum CodingKeys: String, CodingKey {
        case token, capabilities, mode
        case baseURL = "base_url"
        case principalId = "principal_id"
        case actingAs = "acting_as"
        case expiresAt = "expires_at"
    }
}

/// `POST /consent-check` response: the consent ledger's answer, with evidence to store alongside each use of the data.
struct ConsentCheckResult: Decodable, Equatable, Sendable {
    let allowed: Bool
    let basis: String?
    let consentId: String?
    /// A number on the demo server; kept as `JSONValue` so any JSON scalar decodes.
    let ledgerEventId: JSONValue?
    let ledgerHash: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case allowed, basis
        case consentId = "consent_id"
        case ledgerEventId = "ledger_event_id"
        case ledgerHash = "ledger_hash"
        case expiresAt = "expires_at"
    }
}

/// `GET /demo-customers`: the synthetic customers offered on the sign-in screen.
struct DemoCustomer: Decodable, Hashable, Identifiable, Sendable {
    let externalRef: String
    let label: String
    let actsThroughGuardian: Bool

    var id: String { externalRef }

    enum CodingKeys: String, CodingKey {
        case label
        case externalRef = "external_ref"
        case actsThroughGuardian = "acts_through_guardian"
    }
}

/// A non-2xx answer from the session server.
struct SessionServerError: Error, LocalizedError, Equatable {
    let status: Int
    let detail: String

    var errorDescription: String? { "Session server answered \(status): \(detail)" }
}

/// HTTP client for the session server contract. In demo mode `urlSession` is the in-app fake transport.
struct SessionServerClient: Sendable {
    /// e.g. `http://localhost:8787` (session server) or the in-app demo host.
    let serverURL: URL
    /// Used for these calls and handed to `ConsentSession` as `urlSession:`.
    let urlSession: URLSession

    func demoCustomers() async throws -> [DemoCustomer] {
        try await send("GET", "/demo-customers", body: nil)
    }

    /// Mints a principal session. `actingAs: .guardian` only for a customer who acts through a guardian (DPDP s.9);
    /// a real backend must authenticate the guardian before asking for one.
    func mintSession(externalRef: String, actingAs: ActingAs = .dataPrincipal) async throws -> SessionGrant {
        try await send("POST", "/session", body: ["external_ref": externalRef, "acting_as": actingAs.rawValue])
    }

    /// Asks the backend whether `purposeCode` may be used for this customer. Fail closed: treat any error as "no".
    func checkConsent(externalRef: String, purposeCode: String) async throws -> ConsentCheckResult {
        try await send("POST", "/consent-check", body: ["external_ref": externalRef, "purpose_code": purposeCode])
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: String]?) async throws -> T {
        var request = URLRequest(url: serverURL.appendingPathComponent(String(path.dropFirst())))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await urlSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.detail ?? "unexpected response"
            throw SessionServerError(status: status, detail: detail)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// `{"detail": "…"}` error bodies.
    private struct ErrorBody: Decodable {
        let detail: String?
    }
}
