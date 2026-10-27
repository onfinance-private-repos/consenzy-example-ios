// Journey 5: guardian consent for a minor, and a nominee.
// CUST-DEMO-CHILD-7 is a child, so under DPDP s.9 only a verified parent or lawful guardian can consent for them.
//   Step 1: a session minted for the child (acting_as=data_principal) is refused with 422; the SDK surfaces it as
//           `ConsentAPIError.isGuardianRequired`.
//   Step 2: the backend mints a guardian session (acting_as=guardian) and the same grant succeeds.
//   Step 3: a nominee (s.14) is filed with the nomination rights-request type.
// A real backend mints a guardian session only after it has authenticated the guardian, and records the guardian's
// verification in Consenzy once (POST /v1/principals/{id}/guardian-verification).

import OnFinanceConsenzy
import SwiftUI

struct GuardianConsentView: View {
    static let childRef = "CUST-DEMO-CHILD-7"
    static let childName = "Kabir"

    let session: SignedInSession

    @State private var refusal: String?
    @State private var guardianSession: SignedInSession?
    @State private var guardianGrants: [Consent] = []
    @State private var guardianError: String?
    @State private var showGuardianSheet = false

    @State private var nomineeName = "Asha Rao"
    @State private var nomineePhone = "+919812345678"
    @State private var relationship = "parent"
    @State private var nomination: DataRequest?
    @State private var nominationError: String?
    @State private var isBusy = false

    var body: some View {
        List {
            Section {
                Button("Try to consent with the child's own session") { Task { await tryAsChild() } }
                    .disabled(isBusy)
                if let refusal {
                    Label(refusal, systemImage: "hand.raised").foregroundStyle(.orange)
                }
            } header: {
                Text("Step 1: data_principal session for \(Self.childRef)")
            } footer: {
                Text("The server refuses: this principal acts through a guardian (s.9).")
            }

            Section {
                Button("Consent as the guardian") { Task { await consentAsGuardian() } }
                    .disabled(isBusy)
                ForEach(guardianGrants) { consent in
                    Text("Granted \(consent.purposeCode) for \(Self.childName) (\(consent.status.rawValue))")
                        .foregroundStyle(.green)
                }
                if let guardianError {
                    Text(guardianError).foregroundStyle(.red)
                }
                if guardianSession != nil {
                    Button("Open the drop-in ConsentSheet as guardian") { showGuardianSheet = true }
                }
            } header: {
                Text("Step 2: guardian session (acting_as=guardian)")
            }

            Section {
                TextField("Nominee name", text: $nomineeName)
                TextField("Nominee phone (E.164)", text: $nomineePhone)
                    .keyboardType(.phonePad)
                TextField("Relationship", text: $relationship)
                Button("File nomination") { Task { await fileNomination() } }
                    .disabled(isBusy)
                if let nomination {
                    Text("Nomination filed (\(nomination.status.rawValue)), due \(nomination.dueAt.shortDate).")
                        .foregroundStyle(.green)
                }
                if let nominationError {
                    Text(nominationError).foregroundStyle(.red)
                }
            } header: {
                Text("Step 3: nominee (s.14)")
            } footer: {
                Text("Filed through the guardian session once there is one, otherwise through your own session (\(session.externalRef)).")
            }
        }
        .navigationTitle("Guardian consent")
        .sheet(isPresented: $showGuardianSheet) {
            if let guardianSession {
                DropInConsentSheet(session: guardianSession.consent, principalName: Self.childName) { outcome in
                    if case .accepted(let consents) = outcome { guardianGrants = consents }
                    showGuardianSheet = false
                }
            }
        }
        .onDisappear {
            if let consent = guardianSession?.consent { Task { try? await consent.logout() } }
        }
    }

    /// Step 1: mint a data_principal session for the child and try to grant. Expect a 422 the SDK flags as
    /// `isGuardianRequired`.
    private func tryAsChild() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let child = try await ConsentSessionFactory.make(client: session.client, externalRef: Self.childRef, actingAs: .dataPrincipal)
            defer { Task { try? await child.consent.logout() } }
            let profile = try await child.consent.me()
            let notice = try await child.consent.currentNotice()
            do {
                _ = try await child.consent.giveConsent(noticeId: notice.id, purposeIds: Self.purposeIds(notice))
                refusal = "Unexpected: the grant was accepted."
            } catch let error as ConsentAPIError where error.isGuardianRequired {
                refusal = "Refused (\(error.status)): \(error.message). requiresGuardianSession = \(profile.requiresGuardianSession)"
            }
        } catch {
            refusal = ErrorText.describe(error)
        }
    }

    /// Step 2: mint a guardian session for the same child and grant.
    private func consentAsGuardian() async {
        isBusy = true
        defer { isBusy = false }
        guardianError = nil
        do {
            let guardian = try await ConsentSessionFactory.make(client: session.client, externalRef: Self.childRef, actingAs: .guardian)
            guardianSession = guardian
            let profile = try await guardian.consent.me()
            guard profile.isActingAsGuardian else {
                guardianError = "The backend did not mint a guardian session."
                return
            }
            let notice = try await guardian.consent.currentNotice()
            guardianGrants = try await guardian.consent.giveConsent(noticeId: notice.id, purposeIds: Self.purposeIds(notice))
        } catch {
            guardianError = ErrorText.describe(error)
        }
    }

    /// Step 3: `fileDataRequest(.nomination(...))`.
    private func fileNomination() async {
        isBusy = true
        defer { isBusy = false }
        nominationError = nil
        let consent = guardianSession?.consent ?? session.consent
        do {
            nomination = try await consent.fileDataRequest(.nomination(NominationDetails(
                nomineeName: nomineeName,
                nomineePhone: nomineePhone.isEmpty ? nil : nomineePhone,
                relationship: relationship
            )))
        } catch {
            nominationError = ErrorText.describe(error)
        }
    }

    /// The child's app asks for product analytics only.
    static func purposeIds(_ notice: Notice) -> [UUID] {
        notice.purposes.filter { $0.code == "analytics" }.map(\.id)
    }
}
