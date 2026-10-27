// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

#if canImport(SwiftUI)
import OnFinanceConsenzy
import SwiftUI

/// Lets the customer exercise their DPDP rights (ss.11-14): access, correction, completion,
/// updating, erasure, grievance and nomination. Shows earlier requests and their due dates.
public struct RightsRequestForm: View {
    enum Kind: String, CaseIterable, Identifiable {
        case access, correction, completion, updating, erasure, grievance, nomination
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .access: return "Access my data"
            case .correction: return "Correct my data"
            case .completion: return "Complete my data"
            case .updating: return "Update my data"
            case .erasure: return "Erase my data"
            case .grievance: return "Raise a grievance"
            case .nomination: return "Nominate someone"
            }
        }
    }

    struct FieldRow: Identifiable {
        let id = UUID()
        var name = ""
        var value = ""
    }

    @ObservedObject private var model: ConsentViewModel
    private let onSubmitted: ((DataRequest) -> Void)?

    @State private var kind: Kind = .access
    @State private var note = ""
    @State private var fields: [FieldRow] = [FieldRow()]
    @State private var grievance = ""
    @State private var relatedRequestId: UUID?
    @State private var nomineeName = ""
    @State private var nomineeEmail = ""
    @State private var nomineePhone = ""
    @State private var relationship = ""
    @State private var lastSubmitted: DataRequest?

    public init(model: ConsentViewModel, onSubmitted: ((DataRequest) -> Void)? = nil) {
        self.model = model
        self.onSubmitted = onSubmitted
    }

    public var body: some View {
        Form {
            // Hidden, not just disabled, when the session lacks requests:write (the server would 403).
            if model.profile != nil && !model.canFileRequests {
                Section {
                    Text("Rights requests cannot be filed from this app session.")
                        .foregroundColor(.secondary)
                }
            }

            if model.canFileRequests {
                Section {
                    Picker(selection: $kind) {
                        ForEach(Kind.allCases) { kind in Text(kind.title).tag(kind) }
                    } label: {
                        Text("Request type")
                    }
                }

                Section {
                    detailFields
                } header: {
                    Text("Details")
                }

                submitSection
            }

            if model.canReadRequests && !model.dataRequests.isEmpty {
                Section {
                    ForEach(model.dataRequests) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: Self.label(request.requestType)).font(.headline)
                            Text(verbatim: request.status.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.subheadline)
                            if let channel = request.channel {
                                Text(verbatim: Self.channelLabel(channel))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 4) {
                                Text("Due")
                                Text(request.dueAt, style: .date)
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Your requests")
                }
            }
        }
        .task {
            if model.profile == nil { await model.loadProfile() }
            await model.loadDataRequests()
        }
        .alert(
            Text("Something went wrong"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                Task { await submit() }
            } label: {
                Text("Submit request").frame(maxWidth: .infinity)
            }
            .disabled(model.isSubmitting || !model.canFileRequests)
            if model.isSubmitting {
                ProgressView().accessibilityLabel(Text("Submitting your request"))
            }
            if let lastSubmitted {
                HStack(spacing: 4) {
                    Text("Request received. We will respond by")
                    Text(lastSubmitted.dueAt, style: .date)
                }
                .font(.footnote)
                .accessibilityElement(children: .combine)
            }
        } footer: {
            Text("Requests managed by Consenzy")
        }
    }

    @ViewBuilder
    private var detailFields: some View {
        switch kind {
        case .access:
            TextField(text: $note) { Text("Note (optional)") }
        case .correction, .completion, .updating:
            ForEach($fields) { $row in
                VStack(alignment: .leading) {
                    TextField(text: $row.name) { Text("Field, e.g. email") }
                        .plainIdentifierInput()
                        .accessibilityLabel(Text("Field name"))
                    TextField(text: $row.value) { Text("Correct value") }
                        .accessibilityLabel(Text("Correct value"))
                }
            }
            Button {
                fields.append(FieldRow())
            } label: {
                Text("Add another field")
            }
            .disabled(fields.count >= 50)
            TextField(text: $note) { Text("Note (optional)") }
        case .erasure:
            TextField(text: $note) { Text("Reason (optional)") }
        case .grievance:
            TextEditor(text: $grievance)
                .frame(minHeight: 120)
                .accessibilityLabel(Text("Describe your grievance"))
            if model.canReadRequests && !model.dataRequests.isEmpty {
                Picker(selection: $relatedRequestId) {
                    Text("None").tag(UUID?.none)
                    ForEach(model.dataRequests) { request in
                        Text(verbatim: Self.label(request.requestType)).tag(UUID?.some(request.id))
                    }
                } label: {
                    Text("About an earlier request")
                }
            }
        case .nomination:
            TextField(text: $nomineeName) { Text("Nominee's full name") }
            TextField(text: $relationship) { Text("Relationship to you") }
            TextField(text: $nomineeEmail) { Text("Nominee's email") }
                .plainIdentifierInput()
            TextField(text: $nomineePhone) { Text("Nominee's phone, e.g. +919812345678") }
                .plainIdentifierInput()
        }
    }

    private func submission() -> DataRequestSubmission {
        func optional(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        switch kind {
        case .access:
            return .access(AccessDetails(note: optional(note)))
        case .correction, .completion, .updating:
            var map: [String: JSONValue] = [:]
            for row in fields {
                guard let name = optional(row.name) else { continue }
                map[name.lowercased()] = .string(row.value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let details = CorrectionDetails(fields: map, note: optional(note))
            return kind == .correction ? .correction(details) : kind == .completion ? .completion(details) : .updating(details)
        case .erasure:
            return .erasure(ErasureDetails(reason: optional(note)))
        case .grievance:
            return .grievance(GrievanceDetails(description: grievance.trimmingCharacters(in: .whitespacesAndNewlines),
                                               relatedRequestId: relatedRequestId))
        case .nomination:
            return .nomination(NominationDetails(
                nomineeName: nomineeName.trimmingCharacters(in: .whitespacesAndNewlines),
                nomineeEmail: optional(nomineeEmail),
                nomineePhone: optional(nomineePhone),
                relationship: relationship.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
    }

    private func submit() async {
        let request = submission()
        do {
            try request.validate()
        } catch {
            model.errorMessage = ConsentViewModel.message(for: error)
            return
        }
        if let filed = await model.file(request) {
            lastSubmitted = filed
            note = ""
            fields = [FieldRow()]
            grievance = ""
            relatedRequestId = nil
            nomineeName = ""
            nomineeEmail = ""
            nomineePhone = ""
            relationship = ""
            onSubmitted?(filed)
        }
    }

    static func label(_ type: DataRequestType) -> String {
        switch type {
        case .access: return String(localized: "Access my data")
        case .correction: return String(localized: "Correct my data")
        case .completion: return String(localized: "Complete my data")
        case .updating: return String(localized: "Update my data")
        case .erasure: return String(localized: "Erase my data")
        case .grievance: return String(localized: "Raise a grievance")
        case .nomination: return String(localized: "Nominate someone")
        default: return type.rawValue
        }
    }

    /// "Filed in the app", "Received by WhatsApp", ...: requests the bank recorded from other
    /// channels appear in the same list.
    static func channelLabel(_ channel: DataRequestChannel) -> String {
        switch channel {
        case .app: return String(localized: "Filed in the app")
        case .web: return String(localized: "Filed on the website")
        case .email: return String(localized: "Received by email")
        case .whatsapp: return String(localized: "Received on WhatsApp")
        case .sms: return String(localized: "Received by SMS")
        case .phone: return String(localized: "Received by phone")
        case .branch: return String(localized: "Received at a branch")
        default: return String(localized: "Received by other means")
        }
    }
}

private extension View {
    /// No auto-capitalisation or autocorrect, for field names, emails and phone numbers.
    @ViewBuilder
    func plainIdentifierInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never).disableAutocorrection(true)
        #else
        self.disableAutocorrection(true)
        #endif
    }
}
#endif
