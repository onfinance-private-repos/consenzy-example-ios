// Journey 2: check consent before using data for a purpose.
// "Send me offers" uses personal data for the `marketing` purpose, so before doing it the app asks ITS BACKEND, which
// asks the Consenzy consent ledger (`POST /v1/consents/check` with the org key). The action proceeds only when the
// answer is `allowed`; any error fails closed. The consent_id and ledger_hash are the evidence to store with each use.

import OnFinanceConsenzy
import SwiftUI

struct ConsentCheckView: View {
    let session: SignedInSession
    private let purposeCode = "marketing"

    @State private var result: ConsentCheckResult?
    @State private var outcome: String?
    @State private var isBusy = false

    var body: some View {
        List {
            Section {
                Button {
                    Task { await sendOffers() }
                } label: {
                    HStack {
                        Label("Send me offers", systemImage: "megaphone")
                        if isBusy { Spacer(); ProgressView() }
                    }
                }
                .disabled(isBusy)
            } footer: {
                Text("Checks the \"\(purposeCode)\" purpose with the backend (POST /consent-check) before doing anything.")
            }

            if let outcome {
                Section("Outcome") {
                    Text(outcome).foregroundStyle(result?.allowed == true ? .green : .red)
                }
            }

            if let result, result.allowed {
                Section("Evidence to store with this use of the data") {
                    FieldRow(label: "basis", value: result.basis ?? "-")
                    FieldRow(label: "consent_id", value: result.consentId ?? "-")
                    FieldRow(label: "ledger_event_id", value: result.ledgerEventId?.displayText ?? "-")
                    FieldRow(label: "ledger_hash", value: result.ledgerHash ?? "-")
                    FieldRow(label: "expires_at", value: result.expiresAt ?? "never")
                }
            }

            Section {
                Text("Grant \"Marketing messages\" in journey 1 to see the check pass, then withdraw it in journey 3 to see it fail again.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Check consent")
    }

    private func sendOffers() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let check = try await session.client.checkConsent(externalRef: session.externalRef, purposeCode: purposeCode)
            result = check
            if check.allowed {
                // Only now may the data be used for marketing. A real backend would send the offer here.
                outcome = "Allowed: offers sent (demo). Store the evidence below with this send."
            } else {
                outcome = "Not allowed: no active consent for \(purposeCode). Nothing was sent."
            }
        } catch {
            // Fail closed: an error means do not process.
            result = nil
            outcome = "Check failed, so nothing was sent: \(ErrorText.describe(error))"
        }
    }
}
