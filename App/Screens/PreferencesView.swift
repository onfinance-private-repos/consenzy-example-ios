// Journey 3: preferences centre.
// List the customer's active consents and withdraw one, after a confirmation with an optional reason. Withdrawing must
// be as easy as giving consent (DPDP s.6(4)). The drop-in `ConsentManagerView` does the same in one view.

import OnFinanceConsenzy
import OnFinanceConsenzyUI
import SwiftUI

struct PreferencesView: View {
    let session: SignedInSession

    @State private var consents: [Consent] = []
    @State private var purposeNames: [UUID: String] = [:]
    @State private var pendingWithdrawal: Consent?
    @State private var reason = ""
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            Section("Active consents") {
                if consents.isEmpty && !isLoading {
                    Text("No active consents. Give some in journey 1.").foregroundStyle(.secondary)
                }
                ForEach(consents) { consent in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(purposeNames[consent.purposeId] ?? consent.purposeCode).font(.body.bold())
                            Text("Given \(consent.givenAt.shortDateTime) via \(consent.channel.rawValue)").font(.caption)
                            if let expiresAt = consent.expiresAt {
                                Text("Expires \(expiresAt.shortDate)").font(.caption)
                            }
                        }
                        Spacer()
                        Button("Withdraw", role: .destructive) {
                            reason = ""
                            pendingWithdrawal = consent
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let message {
                Section { Text(message).foregroundStyle(.green) }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                NavigationLink("Open the drop-in ConsentManagerView") { DropInConsentManager(session: session.consent) }
            } footer: {
                Text("ConsentManagerView (OnFinanceConsenzyUI) lists active consents with a confirmed Withdraw and pull to refresh.")
            }
        }
        .navigationTitle("Preferences")
        .task { await load() }
        .refreshable { await load() }
        .alert(
            "Withdraw consent?",
            isPresented: Binding(get: { pendingWithdrawal != nil }, set: { if !$0 { pendingWithdrawal = nil } }),
            presenting: pendingWithdrawal
        ) { consent in
            TextField("Reason (optional)", text: $reason)
            Button("Withdraw", role: .destructive) { Task { await withdraw(consent) } }
            Button("Cancel", role: .cancel) {}
        } message: { consent in
            Text("We will stop using your data for \(purposeNames[consent.purposeId] ?? consent.purposeCode).")
        }
    }

    /// `GET /v1/me/consents?active_only=true`, plus the notice for purpose display names.
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            consents = try await session.consent.listConsents(activeOnly: true)
            let notice = try await session.consent.currentNotice()
            purposeNames = Dictionary(uniqueKeysWithValues: notice.purposes.map { ($0.id, $0.name) })
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }

    /// `POST /v1/me/consents/{id}/withdraw`. Not retried automatically by the SDK.
    private func withdraw(_ consent: Consent) async {
        errorMessage = nil
        do {
            let withdrawn = try await session.consent.withdrawConsent(id: consent.id, reason: reason)
            message = "Withdrawn \(withdrawn.purposeCode) at \(withdrawn.withdrawnAt?.shortDateTime ?? "now")."
            await load()
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }
}

/// The drop-in preferences list.
struct DropInConsentManager: View {
    @StateObject private var model: ConsentViewModel

    init(session: ConsentSession) {
        _model = StateObject(wrappedValue: ConsentViewModel(session: session))
    }

    var body: some View {
        ConsentManagerView(model: model)
            .navigationTitle("ConsentManagerView")
    }
}
