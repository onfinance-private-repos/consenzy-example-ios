// The example's journeys, end to end through the real SDK (`ConsentSession`) against the in-app demo backend over the
// fake HTTP transport (`DemoURLProtocol`). Each test gets its own `DemoBackend`, so state never leaks between tests.

import OnFinanceConsenzy
import XCTest
@testable import ConsenzyExample

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date()

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(_ seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }
}

final class JourneyTests: XCTestCase {
    private let adult = "CUST-DEMO-0001"
    private let child = "CUST-DEMO-CHILD-7"

    private var clock: TestClock!
    private var backend: DemoBackend!
    private var client: SessionServerClient!

    override func setUp() {
        super.setUp()
        let clock = TestClock()
        self.clock = clock
        backend = DemoBackend(now: { clock.now })
        client = SessionServerClient(serverURL: backend.baseURL, urlSession: backend.makeURLSession())
    }

    private func signIn(_ ref: String, actingAs: ActingAs = .dataPrincipal) async throws -> SignedInSession {
        try await ConsentSessionFactory.make(client: client, externalRef: ref, actingAs: actingAs)
    }

    private func purposeId(_ notice: Notice, _ code: String) -> UUID {
        notice.purposes.first { $0.code == code }!.id
    }

    // MARK: Session

    func testSessionMintReturnsPrincipalTokenAndBaseURL() async throws {
        let session = try await signIn(adult)
        XCTAssertTrue(session.grant.token.hasPrefix("cps_"))
        XCTAssertEqual(session.grant.baseURL, backend.baseURL.absoluteString)
        XCTAssertEqual(session.grant.mode, "demo")
        let me = try await session.consent.me()
        XCTAssertEqual(me.externalRef, adult)
        XCTAssertEqual(me.actingAs, .dataPrincipal)
        XCTAssertTrue(me.canGiveConsent && me.canFileRequests && me.canReadRequests)
    }

    func testUnknownCustomerIsRefusedByTheBackend() async throws {
        do {
            _ = try await client.mintSession(externalRef: "CUST-UNKNOWN")
            XCTFail("expected 403")
        } catch let error as SessionServerError {
            XCTAssertEqual(error.status, 403)
        }
    }

    func testOrganisationKeyIsRejectedBeforeAnyRequest() async throws {
        let consent = ConsentSession(
            baseURL: backend.baseURL,
            sessionProvider: { "cdm_" + "placeholder-not-a-key" },
            urlSession: backend.makeURLSession()
        )
        do {
            _ = try await consent.me()
            XCTFail("expected organizationAPIKeyRejected")
        } catch let error as ConsentClientError {
            XCTAssertEqual(error, .organizationAPIKeyRejected)
        }
    }

    func testLogoutRevokesTokenAndProviderMintsANewOne() async throws {
        let session = try await signIn(adult)
        _ = try await session.consent.me()
        try await session.consent.logout()
        // The old token is revoked server-side; the SDK asks the provider for a new one and carries on.
        let me = try await session.consent.me()
        XCTAssertEqual(me.externalRef, adult)
    }

    // MARK: Journey 1: notice and consent

    func testNoticeLanguageAndEnglishFallback() async throws {
        let session = try await signIn(adult)
        let english = try await session.consent.currentNotice(language: .english)
        XCTAssertEqual(english.language, .english)
        XCTAssertEqual(english.purposes.map(\.code), ["marketing", "analytics", "credit_offers"])
        XCTAssertEqual(english.purposes[0].dataCategories, ["name", "email", "phone"])
        XCTAssertEqual(english.purposes[0].retentionDays, 365)

        let hindi = try await session.consent.currentNotice(language: .hindi)
        XCTAssertEqual(hindi.language, .hindi)
        XCTAssertEqual(hindi.id, english.id)
        XCTAssertNotEqual(hindi.title, english.title)

        let tamil = try await session.consent.currentNotice(language: .tamil) // not published: falls back to English
        XCTAssertEqual(tamil.language, .english)
        XCTAssertEqual(tamil.title, english.title)

        let preferred = try await session.consent.currentNotice() // the principal's preferred language
        XCTAssertEqual(preferred.language, .english)
    }

    func testGrantListSupersedeAndWithdraw() async throws {
        let session = try await signIn(adult)
        let notice = try await session.consent.currentNotice()
        let granted = try await session.consent.giveConsent(
            noticeId: notice.id, purposeIds: [purposeId(notice, "marketing"), purposeId(notice, "analytics")]
        )
        XCTAssertEqual(granted.map(\.purposeCode), ["marketing", "analytics"])
        XCTAssertTrue(granted.allSatisfy { $0.isActive && $0.channel == .mobileApp })

        // Granting marketing again supersedes the earlier marketing consent.
        let again = try await session.consent.giveConsent(noticeId: notice.id, purposeIds: [purposeId(notice, "marketing")])
        var active = try await session.consent.listConsents(activeOnly: true)
        XCTAssertEqual(Set(active.map(\.purposeCode)), ["marketing", "analytics"])
        XCTAssertTrue(active.contains { $0.id == again[0].id })
        let all = try await session.consent.listConsents()
        XCTAssertEqual(all.first { $0.id == granted[0].id }?.status, .superseded)

        let withdrawn = try await session.consent.withdrawConsent(id: again[0].id, reason: "No longer interested")
        XCTAssertEqual(withdrawn.status, .withdrawn)
        XCTAssertEqual(withdrawn.withdrawalReason, "No longer interested")
        XCTAssertNotNil(withdrawn.withdrawnAt)
        active = try await session.consent.listConsents(activeOnly: true)
        XCTAssertEqual(active.map(\.purposeCode), ["analytics"])

        // Withdrawing twice is a conflict.
        do {
            _ = try await session.consent.withdrawConsent(id: again[0].id)
            XCTFail("expected 409")
        } catch let error as ConsentAPIError {
            XCTAssertTrue(error.isConflict)
        }
    }

    func testIdempotencyKeyReplaysTheFirstGrant() async throws {
        let session = try await signIn(adult)
        let notice = try await session.consent.currentNotice()
        let ids = [purposeId(notice, "analytics")]
        let first = try await session.consent.giveConsent(noticeId: notice.id, purposeIds: ids, idempotencyKey: "demo-key-1")
        let replay = try await session.consent.giveConsent(noticeId: notice.id, purposeIds: ids, idempotencyKey: "demo-key-1")
        XCTAssertEqual(first.map(\.id), replay.map(\.id))
        let active = try await session.consent.listConsents(activeOnly: true)
        XCTAssertEqual(active.count, 1)
    }

    // MARK: Journey 2: consent check

    func testConsentCheckFollowsTheLedger() async throws {
        var check = try await client.checkConsent(externalRef: adult, purposeCode: "marketing")
        XCTAssertFalse(check.allowed)
        XCTAssertNil(check.consentId)

        let session = try await signIn(adult)
        let notice = try await session.consent.currentNotice()
        let granted = try await session.consent.giveConsent(noticeId: notice.id, purposeIds: [purposeId(notice, "marketing")])

        check = try await client.checkConsent(externalRef: adult, purposeCode: "marketing")
        XCTAssertTrue(check.allowed)
        XCTAssertEqual(check.basis, "consent")
        XCTAssertEqual(check.consentId, granted[0].id.uuidString.lowercased())
        XCTAssertEqual(check.ledgerHash?.count, 64)
        XCTAssertNotNil(check.ledgerEventId)

        _ = try await session.consent.withdrawConsent(id: granted[0].id, reason: nil)
        check = try await client.checkConsent(externalRef: adult, purposeCode: "marketing")
        XCTAssertFalse(check.allowed)
    }

    // MARK: Journey 4: rights requests

    func testFileRequestsAndTrackStatus() async throws {
        let session = try await signIn(adult)

        // The seeded erasure request that arrived on WhatsApp is already in the list.
        var requests = try await session.consent.listDataRequests()
        XCTAssertEqual(requests.count, 1)
        let seeded = requests[0]
        XCTAssertEqual(seeded.requestType, .erasure)
        XCTAssertEqual(seeded.channel, .whatsapp)
        XCTAssertEqual(seeded.channelReference, "wamid.DEMO-0001")
        XCTAssertEqual(seeded.status, .inProgress)

        let access = try await session.consent.fileDataRequest(.access(AccessDetails(note: "Everything you hold")))
        XCTAssertEqual(access.status, .received)
        XCTAssertEqual(access.channel, .app)
        XCTAssertEqual(access.dueAt.timeIntervalSince(access.receivedAt), 90 * 86_400, accuracy: 1)
        _ = try await session.consent.fileDataRequest(.correction(CorrectionDetails(fields: ["address_line1": .string("12 MG Road")])))
        _ = try await session.consent.fileDataRequest(.erasure(ErasureDetails(reason: "Closed my account")))
        let grievance = try await session.consent.fileDataRequest(
            .grievance(GrievanceDetails(description: "My erasure request is late", relatedRequestId: seeded.id))
        )
        XCTAssertEqual(grievance.details["related_request_id"]?.stringValue, seeded.id.uuidString.lowercased())

        requests = try await session.consent.listDataRequests()
        XCTAssertEqual(Set(requests.map(\.requestType)), [.access, .correction, .erasure, .grievance])
        XCTAssertEqual(requests.count, 5)

        clock.advance(25)
        requests = try await session.consent.listDataRequests()
        XCTAssertEqual(requests.first { $0.id == access.id }?.status, .inProgress)

        clock.advance(40)
        requests = try await session.consent.listDataRequests()
        let done = try XCTUnwrap(requests.first { $0.id == access.id })
        XCTAssertEqual(done.status, .completed)
        XCTAssertNotNil(done.closedAt)
        XCTAssertEqual(requests.first { $0.id == seeded.id }?.status, .inProgress) // seeded requests keep their status
    }

    func testRequestValidationOnDeviceAndOnServer() async throws {
        let session = try await signIn(adult)
        // Checked by the SDK before sending.
        do {
            _ = try await session.consent.fileDataRequest(.correction(CorrectionDetails(fields: ["Bad Field": .string("x")])))
            XCTFail("expected invalidRequest")
        } catch let error as ConsentClientError {
            guard case .invalidRequest = error else { return XCTFail("unexpected \(error)") }
        }
        // Checked by the server: the related request must be one of the principal's own.
        do {
            _ = try await session.consent.fileDataRequest(.grievance(GrievanceDetails(description: "x", relatedRequestId: UUID())))
            XCTFail("expected 404")
        } catch let error as ConsentAPIError {
            XCTAssertTrue(error.isNotFound)
            XCTAssertEqual(error.message, "related data request not found")
        }
    }

    // MARK: Journey 5: guardian consent and nominee

    func testGuardianRefusalThenGuardianSuccess() async throws {
        let childSession = try await signIn(child)
        let childProfile = try await childSession.consent.me()
        XCTAssertTrue(childProfile.actsThroughGuardian)
        XCTAssertTrue(childProfile.requiresGuardianSession)
        let notice = try await childSession.consent.currentNotice()
        do {
            _ = try await childSession.consent.giveConsent(noticeId: notice.id, purposeIds: GuardianConsentView.purposeIds(notice))
            XCTFail("expected the guardian rule to refuse the grant")
        } catch let error as ConsentAPIError {
            XCTAssertEqual(error.status, 422)
            XCTAssertTrue(error.isGuardianRequired)
        }

        let guardian = try await signIn(child, actingAs: .guardian)
        XCTAssertEqual(guardian.grant.actingAs, "guardian")
        let guardianProfile = try await guardian.consent.me()
        XCTAssertTrue(guardianProfile.isActingAsGuardian)
        XCTAssertFalse(guardianProfile.requiresGuardianSession)
        let granted = try await guardian.consent.giveConsent(noticeId: notice.id, purposeIds: GuardianConsentView.purposeIds(notice))
        XCTAssertEqual(granted.map(\.purposeCode), ["analytics"])

        let check = try await client.checkConsent(externalRef: child, purposeCode: "analytics")
        XCTAssertTrue(check.allowed)
    }

    func testGuardianSessionIsRefusedForAnAdult() async throws {
        do {
            _ = try await signIn(adult, actingAs: .guardian)
            XCTFail("expected 422")
        } catch let error as SessionServerError {
            XCTAssertEqual(error.status, 422)
        }
    }

    func testNomination() async throws {
        let guardian = try await signIn(child, actingAs: .guardian)
        let nomination = try await guardian.consent.fileDataRequest(
            .nomination(NominationDetails(nomineeName: "Asha Rao", nomineePhone: "+919812345678", relationship: "parent"))
        )
        XCTAssertEqual(nomination.requestType, .nomination)
        XCTAssertEqual(nomination.details["nominee_name"]?.stringValue, "Asha Rao")

        // A nominee needs an email or a phone number; the SDK checks before sending.
        do {
            _ = try await guardian.consent.fileDataRequest(.nomination(NominationDetails(nomineeName: "Asha Rao", relationship: "parent")))
            XCTFail("expected invalidRequest")
        } catch let error as ConsentClientError {
            guard case .invalidRequest = error else { return XCTFail("unexpected \(error)") }
        }
    }
}
