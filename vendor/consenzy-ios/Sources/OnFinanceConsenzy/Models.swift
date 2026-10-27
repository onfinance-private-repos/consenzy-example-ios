// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

import Foundation

// MARK: - Open enumerations
//
// Server enumerations are modelled as string-backed structs rather than Swift enums so that
// a value added server-side later does not break decoding in apps already in the field.

/// Notice language: English plus the 22 languages of the Eighth Schedule (DPDP s.5(3)).
public struct Language: RawRepresentable, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var id: String { rawValue }

    public static let english = Language(rawValue: "en")
    public static let assamese = Language(rawValue: "as")
    public static let bengali = Language(rawValue: "bn")
    public static let bodo = Language(rawValue: "brx")
    public static let dogri = Language(rawValue: "doi")
    public static let gujarati = Language(rawValue: "gu")
    public static let hindi = Language(rawValue: "hi")
    public static let kannada = Language(rawValue: "kn")
    public static let kashmiri = Language(rawValue: "ks")
    public static let konkani = Language(rawValue: "kok")
    public static let maithili = Language(rawValue: "mai")
    public static let malayalam = Language(rawValue: "ml")
    public static let manipuri = Language(rawValue: "mni")
    public static let marathi = Language(rawValue: "mr")
    public static let nepali = Language(rawValue: "ne")
    public static let odia = Language(rawValue: "or")
    public static let punjabi = Language(rawValue: "pa")
    public static let sanskrit = Language(rawValue: "sa")
    public static let santali = Language(rawValue: "sat")
    public static let sindhi = Language(rawValue: "sd")
    public static let tamil = Language(rawValue: "ta")
    public static let telugu = Language(rawValue: "te")
    public static let urdu = Language(rawValue: "ur")

    public static let allCases: [Language] = [
        .english, .assamese, .bengali, .bodo, .dogri, .gujarati, .hindi, .kannada, .kashmiri, .konkani, .maithili,
        .malayalam, .manipuri, .marathi, .nepali, .odia, .punjabi, .sanskrit, .santali, .sindhi, .tamil, .telugu, .urdu,
    ]

    /// The language's name in its own script, for language pickers.
    public var endonym: String {
        switch rawValue {
        case "en": return "English"
        case "as": return "অসমীয়া"
        case "bn": return "বাংলা"
        case "brx": return "बड़ो"
        case "doi": return "डोगरी"
        case "gu": return "ગુજરાતી"
        case "hi": return "हिन्दी"
        case "kn": return "ಕನ್ನಡ"
        case "ks": return "کٲشُر"
        case "kok": return "कोंकणी"
        case "mai": return "मैथिली"
        case "ml": return "മലയാളം"
        case "mni": return "ꯃꯤꯇꯩꯂꯣꯟ"
        case "mr": return "मराठी"
        case "ne": return "नेपाली"
        case "or": return "ଓଡ଼ିଆ"
        case "pa": return "ਪੰਜਾਬੀ"
        case "sa": return "संस्कृतम्"
        case "sat": return "ᱥᱟᱱᱛᱟᱲᱤ"
        case "sd": return "سنڌي"
        case "ta": return "தமிழ்"
        case "te": return "తెలుగు"
        case "ur": return "اردو"
        default: return rawValue
        }
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ConsentStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let active = ConsentStatus(rawValue: "active")
    public static let withdrawn = ConsentStatus(rawValue: "withdrawn")
    public static let superseded = ConsentStatus(rawValue: "superseded")

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct Channel: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let web = Channel(rawValue: "web")
    public static let mobileApp = Channel(rawValue: "mobile_app")
    public static let branch = Channel(rawValue: "branch")
    public static let callCentre = Channel(rawValue: "call_centre")
    public static let consentManager = Channel(rawValue: "consent_manager")
    public static let api = Channel(rawValue: "api")

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Data Principal rights (DPDP ss.11-14).
public struct DataRequestType: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let access = DataRequestType(rawValue: "access")
    public static let correction = DataRequestType(rawValue: "correction")
    public static let completion = DataRequestType(rawValue: "completion")
    public static let updating = DataRequestType(rawValue: "updating")
    public static let erasure = DataRequestType(rawValue: "erasure")
    public static let grievance = DataRequestType(rawValue: "grievance")
    public static let nomination = DataRequestType(rawValue: "nomination")

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Where a rights request came in. Requests filed through `ConsentSession.fileDataRequest(_:)`
/// are `app`; the bank's backend records requests received on other channels (WhatsApp, email,
/// branch, ...) with its org key, and they show up in the same `listDataRequests()` list.
public struct DataRequestChannel: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let web = DataRequestChannel(rawValue: "web")
    public static let app = DataRequestChannel(rawValue: "app")
    public static let email = DataRequestChannel(rawValue: "email")
    public static let whatsapp = DataRequestChannel(rawValue: "whatsapp")
    public static let sms = DataRequestChannel(rawValue: "sms")
    public static let phone = DataRequestChannel(rawValue: "phone")
    public static let branch = DataRequestChannel(rawValue: "branch")
    public static let other = DataRequestChannel(rawValue: "other")

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct DataRequestStatus: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let received = DataRequestStatus(rawValue: "received")
    public static let inProgress = DataRequestStatus(rawValue: "in_progress")
    public static let awaitingPrincipal = DataRequestStatus(rawValue: "awaiting_principal")
    public static let completed = DataRequestStatus(rawValue: "completed")
    public static let rejected = DataRequestStatus(rawValue: "rejected")
    public static let withdrawn = DataRequestStatus(rawValue: "withdrawn")

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Who the bank's backend authenticated when it minted the principal session (`acting_as`).
public struct ActingAs: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// The Data Principal themself.
    public static let dataPrincipal = ActingAs(rawValue: "data_principal")
    /// The parent or lawful guardian of a child or a person with disability (DPDP s.9, s.2(j)).
    public static let guardian = ActingAs(rawValue: "guardian")

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// What a principal session may do beyond reading the profile, notice and its own consents.
/// The session holds a capability only if the minting API key had the matching scope.
public struct SessionCapability: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Give and withdraw consent (`POST /v1/me/consents`, `POST /v1/me/consents/{id}/withdraw`).
    public static let consentsWrite = SessionCapability(rawValue: "consents:write")
    /// File rights requests (`POST /v1/me/data-requests`).
    public static let requestsWrite = SessionCapability(rawValue: "requests:write")
    /// List the principal's rights requests (`GET /v1/me/data-requests`).
    public static let requestsRead = SessionCapability(rawValue: "requests:read")

    /// Every capability known to this SDK version.
    public static let all: Set<SessionCapability> = [.consentsWrite, .requestsWrite, .requestsRead]

    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Responses

/// `GET /v1/me`
public struct PrincipalProfile: Codable, Hashable, Sendable {
    public let principalId: UUID
    public let externalRef: String
    public let preferredLanguage: Language
    /// True for a child or a person with disability (DPDP s.9, s.2(j)): consent is given by a guardian.
    public let actsThroughGuardian: Bool
    public let guardianVerified: Bool
    /// Who the session was minted for. Defaults to `.dataPrincipal` when an older server omits it;
    /// values unknown to this SDK version are kept as-is.
    public let actingAs: ActingAs
    /// What this session may do. Unknown values are kept (and ignored by the helpers below).
    /// An older server that omits the field gave every session every capability, so that is the default.
    public let capabilities: Set<SessionCapability>

    enum CodingKeys: String, CodingKey {
        case principalId = "principal_id"
        case externalRef = "external_ref"
        case preferredLanguage = "preferred_language"
        case actsThroughGuardian = "acts_through_guardian"
        case guardianVerified = "guardian_verified"
        case actingAs = "acting_as"
        case capabilities
    }

    public init(
        principalId: UUID, externalRef: String, preferredLanguage: Language, actsThroughGuardian: Bool, guardianVerified: Bool,
        actingAs: ActingAs = .dataPrincipal, capabilities: Set<SessionCapability> = SessionCapability.all
    ) {
        self.principalId = principalId
        self.externalRef = externalRef
        self.preferredLanguage = preferredLanguage
        self.actsThroughGuardian = actsThroughGuardian
        self.guardianVerified = guardianVerified
        self.actingAs = actingAs
        self.capabilities = capabilities
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        principalId = try c.decode(UUID.self, forKey: .principalId)
        externalRef = try c.decode(String.self, forKey: .externalRef)
        preferredLanguage = try c.decode(Language.self, forKey: .preferredLanguage)
        actsThroughGuardian = try c.decodeIfPresent(Bool.self, forKey: .actsThroughGuardian) ?? false
        guardianVerified = try c.decodeIfPresent(Bool.self, forKey: .guardianVerified) ?? false
        actingAs = try c.decodeIfPresent(ActingAs.self, forKey: .actingAs) ?? .dataPrincipal
        capabilities = try c.decodeIfPresent([SessionCapability].self, forKey: .capabilities).map(Set.init) ?? SessionCapability.all
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(principalId, forKey: .principalId)
        try c.encode(externalRef, forKey: .externalRef)
        try c.encode(preferredLanguage, forKey: .preferredLanguage)
        try c.encode(actsThroughGuardian, forKey: .actsThroughGuardian)
        try c.encode(guardianVerified, forKey: .guardianVerified)
        try c.encode(actingAs, forKey: .actingAs)
        try c.encode(capabilities.map(\.rawValue).sorted(), forKey: .capabilities)
    }

    public func has(_ capability: SessionCapability) -> Bool { capabilities.contains(capability) }

    /// The session may give and withdraw consent (`consents:write`).
    public var canGiveConsent: Bool { has(.consentsWrite) }
    /// Alias of `canGiveConsent`: withdrawal needs the same capability.
    public var canWithdrawConsent: Bool { has(.consentsWrite) }
    /// The session may file rights requests (`requests:write`).
    public var canFileRequests: Bool { has(.requestsWrite) }
    /// The session may list earlier rights requests (`requests:read`).
    public var canReadRequests: Bool { has(.requestsRead) }
    /// The session was minted for the principal's parent or lawful guardian.
    public var isActingAsGuardian: Bool { actingAs == .guardian }
    /// The principal is a child or a person with disability but this session is not a guardian
    /// session: the server will refuse consent grants with 422. Mint with `acting_as=guardian`.
    public var requiresGuardianSession: Bool { actsThroughGuardian && !isActingAsGuardian }
}

/// A purpose listed on a notice that requires consent.
public struct NoticePurpose: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let code: String
    public let name: String
    public let description: String
    public let dataCategories: [String]
    public let retentionDays: Int?

    enum CodingKeys: String, CodingKey {
        case id, code, name, description
        case dataCategories = "data_categories"
        case retentionDays = "retention_days"
    }

    public init(id: UUID, code: String, name: String, description: String, dataCategories: [String], retentionDays: Int?) {
        self.id = id
        self.code = code
        self.name = name
        self.description = description
        self.dataCategories = dataCategories
        self.retentionDays = retentionDays
    }
}

/// `GET /v1/me/notice`
public struct Notice: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let version: Int
    public let language: Language
    public let title: String
    public let body: String
    public let purposes: [NoticePurpose]

    public init(id: UUID, version: Int, language: Language, title: String, body: String, purposes: [NoticePurpose]) {
        self.id = id
        self.version = version
        self.language = language
        self.title = title
        self.body = body
        self.purposes = purposes
    }
}

/// A per-purpose consent artefact.
public struct Consent: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let principalId: UUID
    public let purposeId: UUID
    public let purposeCode: String
    public let noticeId: UUID
    public let status: ConsentStatus
    public let channel: Channel
    public let consentManagerRef: String?
    public let givenAt: Date
    public let expiresAt: Date?
    public let withdrawnAt: Date?
    public let withdrawalReason: String?
    public let createdAt: Date
    public let updatedAt: Date

    public var isActive: Bool { status == .active }

    enum CodingKeys: String, CodingKey {
        case id, status, channel
        case principalId = "principal_id"
        case purposeId = "purpose_id"
        case purposeCode = "purpose_code"
        case noticeId = "notice_id"
        case consentManagerRef = "consent_manager_ref"
        case givenAt = "given_at"
        case expiresAt = "expires_at"
        case withdrawnAt = "withdrawn_at"
        case withdrawalReason = "withdrawal_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: UUID, principalId: UUID, purposeId: UUID, purposeCode: String, noticeId: UUID, status: ConsentStatus,
        channel: Channel, consentManagerRef: String? = nil, givenAt: Date, expiresAt: Date? = nil,
        withdrawnAt: Date? = nil, withdrawalReason: String? = nil, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.principalId = principalId
        self.purposeId = purposeId
        self.purposeCode = purposeCode
        self.noticeId = noticeId
        self.status = status
        self.channel = channel
        self.consentManagerRef = consentManagerRef
        self.givenAt = givenAt
        self.expiresAt = expiresAt
        self.withdrawnAt = withdrawnAt
        self.withdrawalReason = withdrawalReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A Data Principal rights request and its statutory deadline.
public struct DataRequest: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let principalId: UUID
    public let requestType: DataRequestType
    public let status: DataRequestStatus
    /// Where the request came in (`app`, `web`, `whatsapp`, `email`, `branch`, ...).
    /// Nil from servers older than the channel field.
    public let channel: DataRequestChannel?
    /// An opaque id from that channel (message id, ticket number), if the backend recorded one.
    public let channelReference: String?
    public let details: [String: JSONValue]
    public let response: [String: JSONValue]?
    public let assignedTo: String?
    /// Statutory response deadline.
    public let dueAt: Date
    public let receivedAt: Date
    public let closedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, channel, details, response
        case principalId = "principal_id"
        case channelReference = "channel_reference"
        case requestType = "request_type"
        case assignedTo = "assigned_to"
        case dueAt = "due_at"
        case receivedAt = "received_at"
        case closedAt = "closed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
