// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

import Foundation

/// `GET /v1/me/breach-notices`: a personal data breach intimation sent to the signed-in
/// principal (DPDP Rules r.7(1)).
///
/// `subject` and `body` are plain text written by the organisation. Show them with
/// `Text(verbatim:)` (or an equivalent plain-text view); never render them as HTML or Markdown.
public struct BreachNotice: Codable, Hashable, Sendable, Identifiable {
    public let noticeId: UUID
    public let breachId: UUID
    public let language: Language
    public let subject: String
    public let body: String
    public let dataCategories: [String]
    public let generatedAt: Date
    public let acknowledgedAt: Date?

    public var id: UUID { noticeId }

    /// The principal has tapped "I have read this" (the server keeps the first time).
    public var isAcknowledged: Bool { acknowledgedAt != nil }

    enum CodingKeys: String, CodingKey {
        case language, subject, body
        case noticeId = "notice_id"
        case breachId = "breach_id"
        case dataCategories = "data_categories"
        case generatedAt = "generated_at"
        case acknowledgedAt = "acknowledged_at"
    }

    public init(
        noticeId: UUID, breachId: UUID, language: Language, subject: String, body: String,
        dataCategories: [String], generatedAt: Date, acknowledgedAt: Date? = nil
    ) {
        self.noticeId = noticeId
        self.breachId = breachId
        self.language = language
        self.subject = subject
        self.body = body
        self.dataCategories = dataCategories
        self.generatedAt = generatedAt
        self.acknowledgedAt = acknowledgedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        noticeId = try c.decode(UUID.self, forKey: .noticeId)
        breachId = try c.decode(UUID.self, forKey: .breachId)
        language = try c.decode(Language.self, forKey: .language)
        subject = try c.decode(String.self, forKey: .subject)
        body = try c.decode(String.self, forKey: .body)
        dataCategories = try c.decodeIfPresent([String].self, forKey: .dataCategories) ?? []
        generatedAt = try c.decode(Date.self, forKey: .generatedAt)
        acknowledgedAt = try c.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
    }
}

extension Array where Element == BreachNotice {
    /// Newest `generatedAt` first; ties broken by notice id so the order is stable.
    public func sortedNewestFirst() -> [BreachNotice] {
        sorted {
            $0.generatedAt != $1.generatedAt
                ? $0.generatedAt > $1.generatedAt
                : $0.noticeId.uuidString < $1.noticeId.uuidString
        }
    }

    /// How many notices are not yet acknowledged, e.g. for a badge.
    public var unacknowledgedCount: Int { filter { !$0.isAcknowledged }.count }
}
