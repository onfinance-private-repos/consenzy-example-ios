// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

import Foundation

/// s.11: a summary of the personal data processed and the processing activities.
public struct AccessDetails: Codable, Hashable, Sendable {
    public var note: String?
    public init(note: String? = nil) { self.note = note }
}

/// s.12(1)-(2): correction, completion or updating of personal data.
public struct CorrectionDetails: Codable, Hashable, Sendable {
    /// Field name (`^[a-z][a-z0-9_]{0,63}$`) to the corrected value. 1 to 50 entries.
    public var fields: [String: JSONValue]
    public var note: String?
    public init(fields: [String: JSONValue], note: String? = nil) {
        self.fields = fields
        self.note = note
    }
}

/// s.12(3): erasure, unless retention is necessary for the specified purpose or by law.
public struct ErasureDetails: Codable, Hashable, Sendable {
    public var reason: String?
    public init(reason: String? = nil) { self.reason = reason }
}

/// s.13: grievance redressal.
public struct GrievanceDetails: Codable, Hashable, Sendable {
    public var description: String
    /// One of the principal's own earlier requests that this grievance is about.
    public var relatedRequestId: UUID?

    enum CodingKeys: String, CodingKey {
        case description
        case relatedRequestId = "related_request_id"
    }

    public init(description: String, relatedRequestId: UUID? = nil) {
        self.description = description
        self.relatedRequestId = relatedRequestId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(relatedRequestId?.uuidString.lowercased(), forKey: .relatedRequestId)
    }
}

/// s.14: nominate an individual to exercise rights on death or incapacity.
public struct NominationDetails: Codable, Hashable, Sendable {
    public var nomineeName: String
    public var nomineeEmail: String?
    /// E.164, e.g. `+919812345678`.
    public var nomineePhone: String?
    public var relationship: String

    enum CodingKeys: String, CodingKey {
        case relationship
        case nomineeName = "nominee_name"
        case nomineeEmail = "nominee_email"
        case nomineePhone = "nominee_phone"
    }

    public init(nomineeName: String, nomineeEmail: String? = nil, nomineePhone: String? = nil, relationship: String) {
        self.nomineeName = nomineeName
        self.nomineeEmail = nomineeEmail
        self.nomineePhone = nomineePhone
        self.relationship = relationship
    }
}

/// A rights request to file with `ConsentSession.fileDataRequest(_:)`. Each case carries the
/// details the server requires for that request type (`DETAILS_BY_TYPE` on the server).
public enum DataRequestSubmission: Hashable, Sendable {
    case access(AccessDetails = .init())
    case correction(CorrectionDetails)
    case completion(CorrectionDetails)
    case updating(CorrectionDetails)
    case erasure(ErasureDetails = .init())
    case grievance(GrievanceDetails)
    case nomination(NominationDetails)

    public var requestType: DataRequestType {
        switch self {
        case .access: return .access
        case .correction: return .correction
        case .completion: return .completion
        case .updating: return .updating
        case .erasure: return .erasure
        case .grievance: return .grievance
        case .nomination: return .nomination
        }
    }

    /// Client-side checks mirroring the server's validators, so obvious mistakes fail fast
    /// without a round trip. The server remains authoritative.
    public func validate() throws {
        func text(_ value: String?, _ field: String, max: Int, required: Bool = false) throws {
            guard let value else {
                if required { throw ConsentClientError.invalidRequest("\(field) is required") }
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { throw ConsentClientError.invalidRequest("\(field) must not be empty") }
            if trimmed.count > max { throw ConsentClientError.invalidRequest("\(field) must be at most \(max) characters") }
        }
        switch self {
        case .access(let d):
            try text(d.note, "note", max: 1000)
        case .correction(let d), .completion(let d), .updating(let d):
            guard (1...50).contains(d.fields.count) else {
                throw ConsentClientError.invalidRequest("fields must contain between 1 and 50 entries")
            }
            for key in d.fields.keys where !Self.isFieldName(key) {
                throw ConsentClientError.invalidRequest("invalid field name '\(key)'")
            }
            try text(d.note, "note", max: 1000)
        case .erasure(let d):
            try text(d.reason, "reason", max: 1000)
        case .grievance(let d):
            try text(d.description, "description", max: 4000, required: true)
        case .nomination(let d):
            try text(d.nomineeName, "nominee_name", max: 200, required: true)
            try text(d.relationship, "relationship", max: 128, required: true)
            if d.nomineeEmail == nil && d.nomineePhone == nil {
                throw ConsentClientError.invalidRequest("nominee_email or nominee_phone is required")
            }
            if let phone = d.nomineePhone, !Self.isE164(phone) {
                throw ConsentClientError.invalidRequest("nominee_phone must be E.164, e.g. +919812345678")
            }
        }
    }

    static func isFieldName(_ s: String) -> Bool {
        let chars = Array(s.utf8)
        guard let first = chars.first, (97...122).contains(first), chars.count <= 64 else { return false }
        return chars.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 95 }
    }

    static func isE164(_ s: String) -> Bool {
        let chars = Array(s.utf8)
        guard chars.count >= 8, chars.count <= 16, chars[0] == 43, chars[1] != 48 else { return false }
        return chars.dropFirst().allSatisfy { (48...57).contains($0) }
    }
}

struct DataRequestBody: Encodable {
    let submission: DataRequestSubmission

    enum CodingKeys: String, CodingKey {
        case requestType = "request_type"
        case details
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(submission.requestType, forKey: .requestType)
        switch submission {
        case .access(let d): try container.encode(d, forKey: .details)
        case .correction(let d), .completion(let d), .updating(let d): try container.encode(d, forKey: .details)
        case .erasure(let d): try container.encode(d, forKey: .details)
        case .grievance(let d): try container.encode(d, forKey: .details)
        case .nomination(let d): try container.encode(d, forKey: .details)
        }
    }
}
