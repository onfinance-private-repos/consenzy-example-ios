import Foundation
import OnFinanceConsenzy

/// Which backend the app talks to.
enum BackendMode: String, CaseIterable, Identifiable {
    /// Zero setup: an in-memory fake answers over a fake HTTP transport (see App/Demo). The default.
    case inAppDemo
    /// The example session server (demo or live mode), e.g. `http://localhost:8787` from the simulator.
    case sessionServer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inAppDemo: return "In-app demo"
        case .sessionServer: return "Session server"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var mode: BackendMode = .inAppDemo
    @Published var sessionServerURL = "http://localhost:8787"
    @Published private(set) var signedIn: SignedInSession?

    /// The client for the selected backend. In demo mode its `URLSession` is the in-app fake transport.
    func makeClient() throws -> SessionServerClient {
        switch mode {
        case .inAppDemo:
            let demo = DemoBackend.shared
            return SessionServerClient(serverURL: demo.baseURL, urlSession: demo.makeURLSession())
        case .sessionServer:
            let trimmed = sessionServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https", url.host != nil else {
                throw SessionServerError(status: 0, detail: "Enter a session server URL such as http://localhost:8787")
            }
            return SessionServerClient(serverURL: url, urlSession: URLSession(configuration: .ephemeral))
        }
    }

    func signIn(externalRef: String, actingAs: ActingAs) async throws {
        signedIn = try await ConsentSessionFactory.make(client: try makeClient(), externalRef: externalRef, actingAs: actingAs)
    }

    /// Revokes the `cps_` token server-side (`POST /v1/me/logout`) and forgets the session.
    func signOut() async {
        if let session = signedIn?.consent {
            try? await session.logout()
        }
        signedIn = nil
    }
}
