// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

#if canImport(SwiftUI)
import OnFinanceConsenzy
import SwiftUI

/// Lists the personal data breach notices sent to the customer (DPDP Rules r.7(1)), newest
/// first, each with an "I have read this" button until it is acknowledged.
///
/// Subject, body and data categories come from the server and are shown with
/// `Text(verbatim:)`: they are never interpreted as HTML, Markdown or localisation keys.
public struct BreachNoticesView: View {
    @ObservedObject private var model: ConsentViewModel

    public init(model: ConsentViewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                if model.breachNotices.isEmpty && !model.isLoading {
                    Text("There are no data breach notices for you.")
                        .foregroundColor(.secondary)
                }
                ForEach(model.breachNotices) { notice in
                    row(notice)
                }
            } header: {
                Text("Data breach notices")
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("We are required to tell you about personal data breaches that affect you.")
                    Text("Consent managed by Consenzy")
                }
            }
        }
        .overlay {
            if model.isLoading && model.breachNotices.isEmpty {
                ProgressView().accessibilityLabel(Text("Loading data breach notices"))
            }
        }
        .task { await model.loadBreachNotices() }
        .refreshable { await model.loadBreachNotices() }
        .alert(
            Text("Something went wrong"),
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func row(_ notice: BreachNotice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !notice.isAcknowledged {
                Text("Unread")
                    .font(.caption.bold())
                    .foregroundColor(.red)
            }
            Text(verbatim: notice.subject)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 4) {
                Text("Received")
                Text(notice.generatedAt, style: .date)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            .accessibilityElement(children: .combine)
            Text(verbatim: notice.body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if !notice.dataCategories.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Data affected:")
                    Text(verbatim: notice.dataCategories.joined(separator: ", "))
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            if let acknowledgedAt = notice.acknowledgedAt {
                HStack(spacing: 4) {
                    Text("You read this on")
                    Text(acknowledgedAt, style: .date)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                .accessibilityElement(children: .combine)
            } else if model.acknowledgingBreachId == notice.breachId {
                ProgressView().accessibilityLabel(Text("Saving"))
            } else {
                Button {
                    Task { await model.acknowledge(notice) }
                } label: {
                    Text("I have read this")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.acknowledgingBreachId != nil)
                .accessibilityLabel(Text("I have read this: \(Text(verbatim: notice.subject))"))
            }
        }
        .padding(.vertical, 4)
    }
}

/// A small count pill for a menu row or tab, e.g. `BreachNoticesBadge(count: model.unacknowledgedBreachNoticeCount)`.
/// Draws nothing when `count` is 0; shows "99+" above 99. VoiceOver reads "N unread data breach notices".
public struct BreachNoticesBadge: View {
    private let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        if count > 0 {
            Text(verbatim: count > 99 ? "99+" : String(count))
                .font(.caption2.bold())
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20)
                .background(Capsule().fill(Color.red))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(count) unread data breach notices"))
        }
    }
}
#endif
