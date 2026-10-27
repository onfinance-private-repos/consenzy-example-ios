// Builds the SDK's `ConsentSession` for a signed-in customer. This is the token-provider wiring every app needs:
// the SDK calls `sessionProvider` the first time it needs a token and again once after a 401, and the provider asks
// YOUR backend for a fresh `cps_…` token. No API key is ever present in the app.

import Foundation
import OnFinanceConsenzy

/// Everything the screens need for one signed-in customer.
struct SignedInSession: Sendable {
    let client: SessionServerClient
    let externalRef: String
    let actingAs: ActingAs
    /// The first `POST /session` answer (base URL, capabilities, expiry) for display.
    let grant: SessionGrant
    /// The Consenzy SDK client. All `/v1/me` calls in the screens go through this.
    let consent: ConsentSession
}

enum ConsentSessionFactory {
    /// Mints a session through the backend, then builds a `ConsentSession` pointed at the base URL it returned.
    static func make(client: SessionServerClient, externalRef: String, actingAs: ActingAs = .dataPrincipal) async throws -> SignedInSession {
        let grant = try await client.mintSession(externalRef: externalRef, actingAs: actingAs)
        guard let baseURL = URL(string: grant.baseURL) else {
            throw SessionServerError(status: 0, detail: "invalid base_url \(grant.baseURL)")
        }
        // The first token is the one just minted; after a 401 (expired or revoked) the provider mints a new one.
        let tokens = TokenSource(first: grant.token) {
            try await client.mintSession(externalRef: externalRef, actingAs: actingAs).token
        }
        let consent = ConsentSession(
            baseURL: baseURL, // e.g. https://consenzy.onfinance.ai in live mode
            sessionProvider: { try await tokens.next() },
            urlSession: client.urlSession
        )
        return SignedInSession(client: client, externalRef: externalRef, actingAs: actingAs, grant: grant, consent: consent)
    }
}

/// Hands out the prefetched token once, then mints fresh ones. `ConsentSession` caches whatever this returns and
/// coalesces concurrent calls, so this is only called again after a 401.
actor TokenSource {
    private var prefetched: String?
    private let mint: @Sendable () async throws -> String

    init(first: String?, mint: @escaping @Sendable () async throws -> String) {
        self.prefetched = first
        self.mint = mint
    }

    func next() async throws -> String {
        if let token = prefetched {
            prefetched = nil
            return token
        }
        return try await mint()
    }
}
