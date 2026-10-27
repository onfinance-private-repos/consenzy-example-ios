// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

#if canImport(SwiftUI)
import OnFinanceConsenzy
import SwiftUI

/// Shows the current consent notice with one switch per purpose.
///
/// DPDP-aligned defaults:
/// * every purpose starts **off**; consent is recorded only for purposes the customer turns on;
/// * "Accept selected" and "Reject all" use the same style and size;
/// * the notice can be read in any of the 23 supported languages (falls back to English).
///
/// Uses system fonts only (Dynamic Type) and loads no remote fonts or images.
public struct ConsentSheet: View {
    public enum Outcome {
        /// Consent recorded for these purposes.
        case accepted([Consent])
        /// The customer declined everything. Nothing was recorded.
        case rejected
    }

    @ObservedObject private var model: ConsentViewModel
    private let principalName: String?
    private let onFinish: (Outcome) -> Void

    /// - Parameter principalName: the name of the child or person with disability, shown as
    ///   "You are acting as guardian for ..." when the session was minted with `acting_as=guardian`.
    public init(model: ConsentViewModel, principalName: String? = nil, onFinish: @escaping (Outcome) -> Void) {
        self.model = model
        self.principalName = principalName
        self.onFinish = onFinish
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                languagePicker
                sessionContext
                if let notice = model.notice {
                    noticeContent(notice)
                } else if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Text("Loading consent notice"))
                }
                actions
                footer
            }
            .padding()
        }
        .task {
            if model.profile == nil { await model.loadProfile() }
            if model.notice == nil { await model.loadNotice() }
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

    private var languagePicker: some View {
        Picker(
            selection: Binding(
                get: { model.requestedLanguage ?? model.notice?.language ?? .english },
                set: { language in Task { await model.loadNotice(language: language) } }
            )
        ) {
            ForEach(Language.allCases) { language in
                Text(verbatim: language.endonym).tag(language)
            }
        } label: {
            Text("Language")
        }
        .pickerStyle(.menu)
        .accessibilityLabel(Text("Notice language"))
    }

    @ViewBuilder
    private var sessionContext: some View {
        if model.isActingAsGuardian {
            Group {
                if let principalName, !principalName.isEmpty {
                    Text("You are acting as guardian for \(principalName).")
                } else {
                    Text("You are acting as guardian for the person this account belongs to.")
                }
            }
            .font(.subheadline.bold())
        } else if model.requiresGuardianSession {
            Text("A parent or guardian must give this consent.")
                .font(.subheadline.bold())
        } else if model.profile != nil && !model.canGiveConsent {
            Text("Consent cannot be given from this app session.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func noticeContent(_ notice: Notice) -> some View {
        if model.isShowingFallbackLanguage {
            Text("This notice is not yet available in the selected language. Showing English.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        Text(verbatim: notice.title)
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
        Text(verbatim: notice.body)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)

        Text("Choose what you agree to. Nothing is switched on unless you turn it on.")
            .font(.subheadline)
            .foregroundColor(.secondary)

        ForEach(notice.purposes) { purpose in
            Toggle(isOn: Binding(
                get: { model.isSelected(purpose.id) },
                set: { model.setSelected(purpose.id, $0) }
            )) {
                PurposeDescription(purpose: purpose)
            }
            .accessibilityLabel(Text(verbatim: purpose.name))
            .accessibilityHint(Text(verbatim: purpose.description))
            .padding(.vertical, 4)
            Divider()
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    if let granted = await model.acceptSelected() { onFinish(.accepted(granted)) }
                }
            } label: {
                Text("Accept selected").frame(maxWidth: .infinity)
            }
            .disabled(
                model.selectedPurposeIds.isEmpty || model.isSubmitting || model.notice == nil
                    || !model.canGiveConsent || model.requiresGuardianSession
            )
            .accessibilityHint(Text("Gives consent only for the purposes you switched on"))

            Button {
                model.rejectAll()
                onFinish(.rejected)
            } label: {
                Text("Reject all").frame(maxWidth: .infinity)
            }
            .disabled(model.isSubmitting)
            .accessibilityHint(Text("Declines every optional purpose"))

            if model.isSubmitting {
                ProgressView().accessibilityLabel(Text("Saving your choices"))
            }
        }
        // Same style and size for both, so neither choice is nudged.
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("You can withdraw consent at any time from your privacy settings.")
            Text("Consent managed by Consenzy")
                .accessibilityLabel(Text("Consent managed by Consenzy"))
        }
        .font(.footnote)
        .foregroundColor(.secondary)
    }
}

struct PurposeDescription: View {
    let purpose: NoticePurpose

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: purpose.name).font(.headline)
            Text(verbatim: purpose.description)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if !purpose.dataCategories.isEmpty {
                Text("Data used: \(purpose.dataCategories.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let days = purpose.retentionDays {
                Text("Kept for up to \(days) days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
#endif
