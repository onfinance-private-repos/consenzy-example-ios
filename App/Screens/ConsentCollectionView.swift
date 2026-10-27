// Journey 1: consent collection.
// Fetch the current notice in the customer's language (with English fallback), show it itemised, let the customer
// tick purposes (nothing pre-selected, DPDP s.6(1)), and record consent for only those purposes with the headless SDK
// call. The drop-in `ConsentSheet` from OnFinanceConsenzyUI does the same in one view.

import OnFinanceConsenzy
import OnFinanceConsenzyUI
import SwiftUI

struct ConsentCollectionView: View {
    let session: SignedInSession

    /// English, Hindi, and Tamil, which the demo bank has not published, to show the server's English fallback.
    private let languages: [Language] = [.english, .hindi, .tamil]

    @State private var language: Language = .english
    @State private var notice: Notice?
    @State private var selected: Set<UUID> = []
    @State private var idempotencyKey = UUID().uuidString.lowercased()
    @State private var granted: [Consent] = []
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showDropIn = false

    var body: some View {
        List {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(languages) { Text($0.endonym).tag($0) }
                }
                .pickerStyle(.segmented)
                if let notice, notice.language != language {
                    Label("Not published in \(language.endonym); showing \(notice.language.endonym).", systemImage: "globe")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            if let notice {
                Section {
                    Text(verbatim: notice.title).font(.headline)
                    Text(verbatim: notice.body).font(.callout)
                    Text("Notice version \(notice.version)").font(.caption).foregroundStyle(.secondary)
                }

                Section("Purposes (choose any)") {
                    ForEach(notice.purposes) { purpose in
                        PurposeRow(purpose: purpose, isOn: binding(for: purpose.id))
                    }
                }

                Section {
                    Button("Record consent for \(selected.count) purpose(s)") { Task { await recordConsent(notice) } }
                        .disabled(selected.isEmpty || isBusy)
                    Button("Reject all") {
                        selected = [] // records nothing: no consent is the default
                        idempotencyKey = UUID().uuidString.lowercased()
                    }
                }
            } else if isBusy {
                ProgressView()
            }

            if !granted.isEmpty {
                Section("Recorded") {
                    ForEach(granted) { consent in
                        VStack(alignment: .leading) {
                            Text(consent.purposeCode).font(.body.bold())
                            Text("Consent \(consent.id.uuidString.lowercased()), \(consent.status.rawValue), via \(consent.channel.rawValue)")
                                .font(.caption.monospaced())
                        }
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button("Open the drop-in ConsentSheet") { showDropIn = true }
            } footer: {
                Text("ConsentSheet (OnFinanceConsenzyUI) shows the same notice with a language picker, a toggle per purpose and equal Accept / Reject buttons.")
            }
        }
        .navigationTitle("Consent")
        .task(id: language) { await loadNotice() }
        .sheet(isPresented: $showDropIn) {
            DropInConsentSheet(session: session.consent) { outcome in
                if case .accepted(let consents) = outcome { granted = consents }
                showDropIn = false
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { isOn in
                if isOn { selected.insert(id) } else { selected.remove(id) }
                idempotencyKey = UUID().uuidString.lowercased() // a different grant gets a different key
            }
        )
    }

    /// `GET /v1/me/notice?language=…`. The server falls back to English; compare `notice.language` with the request.
    private func loadNotice() async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        do {
            notice = try await session.consent.currentNotice(language: language)
            selected = []
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }

    /// `POST /v1/me/consents` for the ticked purposes only, in the notice's order. Reusing `idempotencyKey` when the
    /// customer taps again after a failure means the server records the grant at most once.
    private func recordConsent(_ notice: Notice) async {
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        let purposeIds = notice.purposes.map(\.id).filter { selected.contains($0) }
        do {
            granted = try await session.consent.giveConsent(
                noticeId: notice.id,
                purposeIds: purposeIds,
                idempotencyKey: idempotencyKey
            )
            selected = []
            idempotencyKey = UUID().uuidString.lowercased()
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }
}

/// One itemised purpose: name, description, data categories and retention, with an opt-in toggle (off by default).
struct PurposeRow: View {
    let purpose: NoticePurpose
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: purpose.name).font(.body.bold())
                Text(verbatim: purpose.description).font(.callout)
                Text("Data: \(purpose.dataCategories.joined(separator: ", "))").font(.caption)
                if let days = purpose.retentionDays {
                    Text("Kept for \(days) days").font(.caption)
                }
            }
        }
    }
}

/// The drop-in sheet. `ConsentViewModel` is an `ObservableObject`, so it lives in a `@StateObject`.
struct DropInConsentSheet: View {
    @StateObject private var model: ConsentViewModel
    private let principalName: String?
    private let onFinish: (ConsentSheet.Outcome) -> Void

    /// - Parameter principalName: for a guardian session, the child's name ("You are acting as guardian for …").
    init(session: ConsentSession, principalName: String? = nil, onFinish: @escaping (ConsentSheet.Outcome) -> Void) {
        _model = StateObject(wrappedValue: ConsentViewModel(session: session))
        self.principalName = principalName
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            ConsentSheet(model: model, principalName: principalName, onFinish: onFinish)
        }
    }
}
