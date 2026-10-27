// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

#if canImport(SwiftUI)
import OnFinanceConsenzy
import Foundation
import SwiftUI

/// Main-actor state shared by `ConsentSheet`, `ConsentManagerView` and `RightsRequestForm`.
@MainActor
public final class ConsentViewModel: ObservableObject {
    /// The notice being shown, or nil before the first load.
    @Published public private(set) var notice: Notice?
    /// The language the customer asked for. The server falls back to English when no notice
    /// exists in that language; compare with `notice?.language`.
    @Published public private(set) var requestedLanguage: Language?
    /// Purposes the customer has switched on. Always starts empty: DPDP s.6(1) requires a clear
    /// affirmative action, so nothing is pre-selected.
    /// Purpose id to on/off. Use `isSelected(_:)` / `setSelected(_:_:)` to bind toggles.
    @Published public var selection: [UUID: Bool] = [:]
    @Published public private(set) var consents: [Consent] = []
    @Published public private(set) var dataRequests: [DataRequest] = []
    /// Personal data breach notices, newest first. Every session can read these.
    @Published public private(set) var breachNotices: [BreachNotice] = []
    /// Breach id of the notice being acknowledged, if any.
    @Published public private(set) var acknowledgingBreachId: UUID?
    /// `GET /v1/me` for the current session: who it acts as and what it may do. Nil until loaded.
    @Published public private(set) var profile: PrincipalProfile?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isSubmitting = false
    /// A user-presentable error from the last operation. Set to nil to dismiss.
    @Published public var errorMessage: String?

    public let session: ConsentSession

    /// Idempotency key reused while the same grant (notice + selection) is re-submitted, so a
    /// customer tapping "Accept" again after a network failure cannot create duplicates.
    private var pendingGrant: (fingerprint: String, key: String)?

    public init(session: ConsentSession, language: Language? = nil) {
        self.session = session
        self.requestedLanguage = language
    }

    // MARK: Session profile and capabilities

    /// Loads `GET /v1/me`. The components call this before showing actions, so that actions the
    /// session cannot perform are hidden or disabled instead of failing with 403.
    public func loadProfile() async {
        do {
            profile = try await session.me()
        } catch {
            report(error)
        }
    }

    /// Accept and withdraw need `consents:write`. False until the profile has loaded.
    public var canGiveConsent: Bool { profile?.canGiveConsent ?? false }
    /// The rights request form needs `requests:write`. False until the profile has loaded.
    public var canFileRequests: Bool { profile?.canFileRequests ?? false }
    /// The list of earlier requests needs `requests:read`. False until the profile has loaded.
    public var canReadRequests: Bool { profile?.canReadRequests ?? false }
    /// The session was minted for the principal's parent or lawful guardian.
    public var isActingAsGuardian: Bool { profile?.isActingAsGuardian ?? false }
    /// The principal is a child or a person with disability and this is not a guardian session:
    /// the server will refuse consent, so the sheet explains instead of offering "Accept".
    public var requiresGuardianSession: Bool { profile?.requiresGuardianSession ?? false }

    // MARK: Notice

    /// Loads the latest notice. Clears any selection, since a new notice must be read afresh.
    public func loadNotice(language: Language? = nil) async {
        if let language { requestedLanguage = language }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await session.currentNotice(language: requestedLanguage)
            notice = loaded
            selection = [:]
            pendingGrant = nil
        } catch {
            report(error)
        }
    }

    /// True when a notice was requested in a language the bank has not published it in.
    public var isShowingFallbackLanguage: Bool {
        guard let requestedLanguage, let notice else { return false }
        return notice.language != requestedLanguage
    }

    public var selectedPurposeIds: Set<UUID> { Set(selection.filter(\.value).keys) }

    public func isSelected(_ purposeId: UUID) -> Bool { selection[purposeId] ?? false }

    public func setSelected(_ purposeId: UUID, _ isOn: Bool) { selection[purposeId] = isOn }

    /// Records consent for the selected purposes only. Returns the new consents, or nil on failure
    /// (see `errorMessage`).
    public func acceptSelected() async -> [Consent]? {
        guard let notice, !selectedPurposeIds.isEmpty, !isSubmitting, canGiveConsent else { return nil }
        // Keep the notice's order so consents come back in the order the customer saw them.
        let selected = selectedPurposeIds
        let ids = notice.purposes.map(\.id).filter { selected.contains($0) }
        let fingerprint = ([notice.id] + ids).map(\.uuidString).joined(separator: ",")
        let key = pendingGrant?.fingerprint == fingerprint ? pendingGrant!.key : UUID().uuidString.lowercased()
        pendingGrant = (fingerprint, key)

        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let granted = try await session.giveConsent(noticeId: notice.id, purposeIds: ids, idempotencyKey: key)
            pendingGrant = nil
            selection = [:]
            mergeConsents(granted)
            return granted
        } catch {
            report(error)
            return nil
        }
    }

    /// "Reject all": records nothing server-side (no consent is the default) and clears the selection.
    public func rejectAll() {
        selection = [:]
        pendingGrant = nil
    }

    // MARK: Consents

    public func loadConsents(activeOnly: Bool = true) async {
        isLoading = true
        defer { isLoading = false }
        do {
            consents = try await session.listConsents(activeOnly: activeOnly)
        } catch {
            report(error)
        }
    }

    /// Withdraws a consent (DPDP s.6(4)). Returns true on success.
    public func withdraw(_ consent: Consent, reason: String? = nil) async -> Bool {
        guard !isSubmitting, canGiveConsent else { return false }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let updated = try await session.withdrawConsent(id: consent.id, reason: reason)
            consents.removeAll { $0.id == updated.id }
            return true
        } catch {
            report(error)
            return false
        }
    }

    /// The purpose's display name from the loaded notice, falling back to its code.
    public func purposeName(for consent: Consent) -> String {
        notice?.purposes.first { $0.id == consent.purposeId }?.name ?? consent.purposeCode
    }

    // MARK: Rights requests

    /// Lists earlier requests. Does nothing when the session lacks `requests:read`.
    public func loadDataRequests() async {
        guard canReadRequests else {
            dataRequests = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            dataRequests = try await session.listDataRequests()
        } catch {
            report(error)
        }
    }

    /// Files a rights request. Returns it on success, or nil (see `errorMessage`).
    public func file(_ submission: DataRequestSubmission) async -> DataRequest? {
        guard !isSubmitting, canFileRequests else { return nil }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let request = try await session.fileDataRequest(submission)
            dataRequests.insert(request, at: 0)
            return request
        } catch {
            report(error)
            return nil
        }
    }

    // MARK: Breach notices

    /// Loads `GET /v1/me/breach-notices` (newest first).
    public func loadBreachNotices() async {
        isLoading = true
        defer { isLoading = false }
        do {
            breachNotices = try await session.listBreachNotices()
        } catch {
            report(error)
        }
    }

    /// Notices not yet acknowledged, for a badge (see `BreachNoticesBadge`).
    public var unacknowledgedBreachNoticeCount: Int { breachNotices.unacknowledgedCount }

    /// "I have read this". Returns true once the notice is acknowledged. Does nothing for a
    /// notice that is already acknowledged or while another acknowledgement is in flight; the
    /// server keeps the first acknowledgement time in any case.
    @discardableResult
    public func acknowledge(_ notice: BreachNotice) async -> Bool {
        if notice.isAcknowledged || breachNotices.first(where: { $0.breachId == notice.breachId })?.isAcknowledged == true {
            return true
        }
        guard acknowledgingBreachId == nil else { return false }
        acknowledgingBreachId = notice.breachId
        defer { acknowledgingBreachId = nil }
        do {
            let updated = try await session.acknowledgeBreachNotice(breachId: notice.breachId)
            breachNotices = breachNotices.map { $0.breachId == updated.breachId ? updated : $0 }.sortedNewestFirst()
            return true
        } catch {
            report(error)
            return false
        }
    }

    // MARK: Helpers

    private func mergeConsents(_ granted: [Consent]) {
        let ids = Set(granted.map(\.id))
        consents = granted.filter(\.isActive) + consents.filter { !ids.contains($0.id) }
    }

    private func report(_ error: Error) {
        if error is CancellationError { return }
        errorMessage = Self.message(for: error)
    }

    /// A user-presentable message for an SDK error.
    public nonisolated static func message(for error: Error) -> String {
        switch error {
        case let error as ConsentAPIError:
            if error.isGuardianRequired {
                return String(localized: "A parent or guardian must give this consent.")
            }
            switch error.status {
            case 403: return String(localized: "You are not allowed to do this in this app session.")
            case 401: return String(localized: "Your session has expired. Please sign in again.")
            case 429: return String(localized: "Too many attempts. Please try again in a moment.")
            case 500...: return String(localized: "The service is temporarily unavailable. Please try again.")
            default: return error.message
            }
        case let error as ConsentClientError:
            switch error {
            case .transport: return String(localized: "Could not connect. Check your connection and try again.")
            case .invalidRequest(let message): return message
            default: return error.description
            }
        default:
            return error.localizedDescription
        }
    }
}
#endif
