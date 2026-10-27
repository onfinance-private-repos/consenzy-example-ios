// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

#if canImport(SwiftUI)
import OnFinanceConsenzy
import SwiftUI

/// Lists the customer's active consents and lets them withdraw any of them (DPDP s.6(4):
/// withdrawal must be as easy as giving consent). Each withdrawal asks for confirmation.
public struct ConsentManagerView: View {
    @ObservedObject private var model: ConsentViewModel
    @State private var pendingWithdrawal: Consent?

    public init(model: ConsentViewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                if model.consents.isEmpty && !model.isLoading {
                    Text("You have not given consent for any optional purpose.")
                        .foregroundColor(.secondary)
                }
                ForEach(model.consents) { consent in
                    row(consent)
                }
            } header: {
                Text("Active consents")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if model.profile != nil && !model.canGiveConsent {
                        Text("Consent cannot be withdrawn from this app session.")
                    }
                    Text("Consent managed by Consenzy")
                }
            }
        }
        .overlay {
            if model.isLoading && model.consents.isEmpty {
                ProgressView().accessibilityLabel(Text("Loading your consents"))
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog(
            Text("Withdraw consent?"),
            isPresented: Binding(get: { pendingWithdrawal != nil }, set: { if !$0 { pendingWithdrawal = nil } }),
            titleVisibility: .visible,
            presenting: pendingWithdrawal
        ) { consent in
            Button(role: .destructive) {
                Task { _ = await model.withdraw(consent) }
            } label: {
                Text("Withdraw")
            }
            Button("Cancel", role: .cancel) {}
        } message: { consent in
            Text("\(model.purposeName(for: consent)) will stop once your withdrawal is processed. Processing that has already happened is not affected.")
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

    private func reload() async {
        // The notice supplies human-readable purpose names.
        if model.profile == nil { await model.loadProfile() }
        if model.notice == nil { await model.loadNotice() }
        await model.loadConsents(activeOnly: true)
    }

    private func row(_ consent: Consent) -> some View {
        let name = model.purposeName(for: consent)
        return VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: name).font(.headline)
            HStack(spacing: 4) {
                Text("Given")
                Text(consent.givenAt, style: .date)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .accessibilityElement(children: .combine)
            if let expiresAt = consent.expiresAt {
                HStack(spacing: 4) {
                    Text("Expires")
                    Text(expiresAt, style: .date)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityElement(children: .combine)
            }
            Button(role: .destructive) {
                pendingWithdrawal = consent
            } label: {
                Text("Withdraw")
            }
            .buttonStyle(.bordered)
            .disabled(model.isSubmitting || !model.canGiveConsent)
            .accessibilityLabel(Text("Withdraw consent for \(name)"))
        }
        .padding(.vertical, 4)
    }
}
#endif
