// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One entry of a 422 validation error (`{"detail": [{"loc": [...], "msg": ..., "type": ...}]}`).
public struct ValidationIssue: Codable, Hashable, Sendable {
    public let type: String?
    /// Path to the offending field, e.g. `["body", "nominee_name"]`. Elements are strings or numbers.
    public let loc: [JSONValue]
    public let msg: String

    public init(type: String?, loc: [JSONValue], msg: String) {
        self.type = type
        self.loc = loc
        self.msg = msg
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type)
        loc = try c.decodeIfPresent([JSONValue].self, forKey: .loc) ?? []
        msg = try c.decode(String.self, forKey: .msg)
    }

    /// The field path without the leading `body` / `query` segment, joined with dots.
    public var field: String {
        let parts = loc.compactMap { value -> String? in
            switch value {
            case .string(let s): return s
            case .number(let n): return String(Int(n))
            default: return nil
            }
        }
        let trimmed = ["body", "query", "path", "header"].contains(parts.first ?? "") ? Array(parts.dropFirst()) : parts
        return trimmed.joined(separator: ".")
    }
}

/// The decoded `detail` of an error response.
public enum ErrorDetail: Hashable, Sendable {
    /// `{"detail": "consent not found"}`
    case message(String)
    /// `{"detail": [{"loc": ..., "msg": ..., "type": ...}, ...]}` (HTTP 422)
    case validation([ValidationIssue])
    /// Any other JSON shape.
    case other(JSONValue)

    /// A single human-readable line.
    public var summary: String {
        switch self {
        case .message(let message):
            return message
        case .validation(let issues):
            return issues.map { $0.field.isEmpty ? $0.msg : "\($0.field): \($0.msg)" }.joined(separator: "; ")
        case .other(let value):
            if let data = try? JSONEncoder.consentDataMaster().encode(value), let s = String(data: data, encoding: .utf8) {
                return s
            }
            return "unknown error"
        }
    }

    static func decode(from data: Data) -> ErrorDetail? {
        struct Envelope: Decodable { let detail: JSONValue }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        switch envelope.detail {
        case .string(let message):
            return .message(message)
        case .array:
            struct Issues: Decodable { let detail: [ValidationIssue] }
            if let issues = try? JSONDecoder().decode(Issues.self, from: data) { return .validation(issues.detail) }
            return .other(envelope.detail)
        default:
            return .other(envelope.detail)
        }
    }
}

/// The API answered with a non-2xx status.
public struct ConsentAPIError: Error, Hashable, Sendable, CustomStringConvertible {
    /// HTTP status code.
    public let status: Int
    /// The decoded `{"detail": ...}`, or nil when the body was not the API's JSON error shape
    /// (for example an HTML page from a proxy in front of the API).
    public let detail: ErrorDetail?
    /// The raw response body.
    public let body: Data

    public init(status: Int, detail: ErrorDetail?, body: Data = Data()) {
        self.status = status
        self.detail = detail
        self.body = body
    }

    public var isUnauthorized: Bool { status == 401 }
    /// 403: for a principal session, it lacks the capability the call needs (see `missingCapability`).
    public var isForbidden: Bool { status == 403 }
    public var isNotFound: Bool { status == 404 }
    public var isConflict: Bool { status == 409 }
    public var isValidationError: Bool { status == 422 }
    public var isRateLimited: Bool { status == 429 }
    public var isServerError: Bool { status >= 500 }

    /// For a 403 `"session lacks capability requests:write"`, the capability the session is missing.
    public var missingCapability: SessionCapability? {
        guard status == 403, case .message(let message) = detail else { return nil }
        let prefix = "session lacks capability "
        guard message.hasPrefix(prefix) else { return nil }
        let raw = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        return raw.isEmpty ? nil : SessionCapability(rawValue: raw)
    }

    /// A 422 refusing consent because the principal is a child or a person with disability and
    /// consent must come from a (verified) parent or lawful guardian, through a session minted
    /// with `acting_as=guardian` (DPDP s.9).
    public var isGuardianRequired: Bool {
        guard status == 422, case .message(let message) = detail else { return false }
        return message.contains("acting_as=guardian") || message.contains("parent or lawful guardian")
    }

    /// Validation issues of a 422, otherwise empty.
    public var validationIssues: [ValidationIssue] {
        if case .validation(let issues) = detail { return issues }
        return []
    }

    public var message: String { detail?.summary ?? HTTPURLResponse.localizedString(forStatusCode: status) }

    public var description: String { "ConsentAPIError(\(status)): \(message)" }
}

/// Errors raised by the SDK itself, before or instead of an HTTP status.
public enum ConsentClientError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The session provider returned an organisation API key (`cdm_…`). Those keys must never be
    /// shipped in an app: mint a principal session on your backend with `POST /v1/principal-sessions`.
    case organizationAPIKeyRejected
    /// The session provider returned something that is not a principal session token (`cps_…`).
    case invalidSessionToken
    /// The request failed client-side validation; the message names the field.
    case invalidRequest(String)
    /// The request never got an HTTP response (offline, DNS, TLS / pinning failure, timeout).
    case transport(code: Int, message: String)
    /// A 2xx response whose body could not be decoded.
    case decoding(String)
    /// The response was not HTTP.
    case invalidResponse

    public var description: String {
        switch self {
        case .organizationAPIKeyRejected:
            return "An organisation API key (cdm_…) was supplied. Mint a principal session token (cps_…) on your backend instead."
        case .invalidSessionToken:
            return "The session provider did not return a principal session token (cps_…)."
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .transport(let code, let message):
            return "Network error \(code): \(message)"
        case .decoding(let message):
            return "Could not decode the response: \(message)"
        case .invalidResponse:
            return "The server response was not HTTP."
        }
    }
}
