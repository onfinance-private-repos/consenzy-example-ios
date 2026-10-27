// Journey 4: Data Principal rights requests.
// File access (s.11), correction (s.12(1)), erasure (s.12(3)) and grievance (s.13) requests with the SDK's typed
// `DataRequestSubmission` details, then track every request with `listDataRequests()`: status, the channel it came in
// on (including the demo customer's erasure request that arrived on WhatsApp) and the statutory due date.
// The drop-in `RightsRequestForm` does the same in one view.

import OnFinanceConsenzy
import OnFinanceConsenzyUI
import SwiftUI

struct RightsRequestsView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case access, correction, erasure, grievance
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    let session: SignedInSession

    @State private var kind: Kind = .access
    @State private var note = ""
    @State private var fieldName = "address_line1"
    @State private var fieldValue = ""
    @State private var reason = ""
    @State private var grievance = ""
    @State private var relatedRequestId: UUID?
    @State private var requests: [DataRequest] = []
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isBusy = false

    var body: some View {
        List {
            Section("File a request") {
                Picker("Right", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                switch kind {
                case .access:
                    TextField("Note (optional)", text: $note)
                case .correction:
                    TextField("Field (e.g. address_line1)", text: $fieldName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Corrected value", text: $fieldValue)
                case .erasure:
                    TextField("Reason (optional)", text: $reason)
                case .grievance:
                    TextField("What went wrong?", text: $grievance, axis: .vertical)
                    Picker("About request", selection: $relatedRequestId) {
                        Text("None").tag(UUID?.none)
                        ForEach(requests) { r in
                            Text("\(r.requestType.rawValue) (\(r.receivedAt.shortDate))").tag(UUID?.some(r.id))
                        }
                    }
                }
                Button("Submit \(kind.rawValue) request") { Task { await file() } }
                    .disabled(isBusy)
            }

            if let message {
                Section { Text(message).foregroundStyle(.green) }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                ForEach(requests) { request in
                    DataRequestRow(request: request)
                }
                Button("Refresh status") { Task { await loadRequests() } }
            } header: {
                Text("My requests")
            } footer: {
                Text("Demo requests move from received to in_progress after 20 s and to completed after 60 s.")
            }

            Section {
                NavigationLink("Open the drop-in RightsRequestForm") { DropInRightsForm(session: session.consent) }
            }
        }
        .navigationTitle("My data rights")
        .task { await loadRequests() }
        .refreshable { await loadRequests() }
    }

    /// The typed submission for the chosen right. The SDK validates it on the device before sending.
    private func submission() -> DataRequestSubmission {
        func optional(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        switch kind {
        case .access:
            return .access(AccessDetails(note: optional(note)))
        case .correction:
            return .correction(CorrectionDetails(fields: [fieldName: .string(fieldValue)]))
        case .erasure:
            return .erasure(ErasureDetails(reason: optional(reason)))
        case .grievance:
            return .grievance(GrievanceDetails(description: grievance, relatedRequestId: relatedRequestId))
        }
    }

    /// `POST /v1/me/data-requests` with an Idempotency-Key the SDK reuses across its retries.
    private func file() async {
        isBusy = true
        defer { isBusy = false }
        message = nil
        errorMessage = nil
        do {
            let filed = try await session.consent.fileDataRequest(submission())
            message = "Filed \(filed.requestType.rawValue) request. Due by \(filed.dueAt.shortDate)."
            await loadRequests()
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }

    /// `GET /v1/me/data-requests`, newest first, including requests the bank recorded from other channels.
    private func loadRequests() async {
        do {
            requests = try await session.consent.listDataRequests()
        } catch {
            errorMessage = ErrorText.describe(error)
        }
    }
}

/// One tracked request: type, status, channel (and channel reference), received and due dates.
struct DataRequestRow: View {
    let request: DataRequest

    private var channelText: String {
        guard let channel = request.channel else { return "unknown channel" }
        if channel == .app { return "this app" }
        if let ref = request.channelReference { return "\(channel.rawValue) (\(ref))" }
        return channel.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(request.requestType.rawValue.capitalized).font(.body.bold())
                Spacer()
                Text(request.status.rawValue)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(request.status == .completed ? Color.green.opacity(0.2) : Color.blue.opacity(0.15)))
            }
            Text("Via \(channelText)").font(.caption)
            Text("Received \(request.receivedAt.shortDate), due \(request.dueAt.shortDate)").font(.caption)
            if let summary = request.response?["summary"]?.stringValue {
                Text(verbatim: summary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The drop-in rights form.
struct DropInRightsForm: View {
    @StateObject private var model: ConsentViewModel

    init(session: ConsentSession) {
        _model = StateObject(wrappedValue: ConsentViewModel(session: session))
    }

    var body: some View {
        RightsRequestForm(model: model)
            .navigationTitle("RightsRequestForm")
    }
}
