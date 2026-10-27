// Home: who is signed in, what the session may do, the five journeys, and logout.

import OnFinanceConsenzy
import SwiftUI

struct HomeView: View {
    let session: SignedInSession
    @EnvironmentObject private var state: AppState
    @State private var profile: PrincipalProfile?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Signed in") {
                FieldRow(label: "Customer (external_ref)", value: session.externalRef)
                FieldRow(label: "Acting as", value: profile?.actingAs.rawValue ?? session.grant.actingAs)
                FieldRow(label: "Capabilities", value: (profile.map { $0.capabilities.map(\.rawValue).sorted() } ?? session.grant.capabilities).joined(separator: ", "))
                FieldRow(label: "Backend", value: "\(session.grant.mode) at \(session.grant.baseURL)")
                if profile?.requiresGuardianSession == true {
                    Label("This customer acts through a guardian: consent needs a guardian session.", systemImage: "person.2")
                        .font(.footnote)
                }
            }

            Section("Journeys") {
                NavigationLink("1. Consent collection") { ConsentCollectionView(session: session) }
                NavigationLink("2. Check consent before use") { ConsentCheckView(session: session) }
                NavigationLink("3. Preferences centre") { PreferencesView(session: session) }
                NavigationLink("4. Rights requests") { RightsRequestsView(session: session) }
                NavigationLink("5. Guardian consent and nominee") { GuardianConsentView(session: session) }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button("Log out", role: .destructive) { Task { await state.signOut() } }
            } footer: {
                Text("Log out calls ConsentSession.logout(), which revokes the cps_ token on the server.")
            }
        }
        .navigationTitle("Privacy")
        .task {
            do {
                profile = try await session.consent.me() // GET /v1/me: acting_as and capabilities
            } catch {
                errorMessage = ErrorText.describe(error)
            }
        }
    }
}
