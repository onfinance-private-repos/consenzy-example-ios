// DEMO ONLY. Nothing in App/Demo is needed in a real app: delete the folder and point the app at your own backend.
//
// The synthetic data behind the in-app demo. `App/Resources/demo-fixtures.json` is a copy of `src/fixtures.json` from
// https://github.com/never2average/consenzy-example-session-server, shared by every Consenzy example app.

import Foundation
import OnFinanceConsenzy

struct DemoFixtures: Decodable {
    struct Principal: Decodable {
        let externalRef: String
        let principalId: String
        let label: String
        let preferredLanguage: String
        let actsThroughGuardian: Bool
        let guardianVerified: Bool

        enum CodingKeys: String, CodingKey {
            case label
            case externalRef = "external_ref"
            case principalId = "principal_id"
            case preferredLanguage = "preferred_language"
            case actsThroughGuardian = "acts_through_guardian"
            case guardianVerified = "guardian_verified"
        }
    }

    struct PurposeText: Decodable {
        let name: String
        let description: String
    }

    struct Translation: Decodable {
        let title: String
        let body: String
        /// Keyed by purpose code.
        let purposes: [String: PurposeText]
    }

    struct NoticeFixture: Decodable {
        let id: String
        let version: Int
        /// Keyed by language code (`en`, `hi`).
        let translations: [String: Translation]
    }

    struct Purpose: Decodable {
        let id: String
        let code: String
        let dataCategories: [String]
        let retentionDays: Int?

        enum CodingKeys: String, CodingKey {
            case id, code
            case dataCategories = "data_categories"
            case retentionDays = "retention_days"
        }
    }

    struct SeedRequest: Decodable {
        let externalRef: String
        let id: String
        let requestType: String
        let status: String
        let channel: String
        let channelReference: String?
        let details: [String: JSONValue]
        let receivedDaysAgo: Double

        enum CodingKeys: String, CodingKey {
            case id, status, channel, details
            case externalRef = "external_ref"
            case requestType = "request_type"
            case channelReference = "channel_reference"
            case receivedDaysAgo = "received_days_ago"
        }
    }

    struct StatusProgression: Decodable {
        let inProgress: Double
        let completed: Double

        enum CodingKeys: String, CodingKey {
            case inProgress = "in_progress"
            case completed
        }
    }

    let principals: [Principal]
    let notice: NoticeFixture
    let purposes: [Purpose]
    let seedDataRequests: [SeedRequest]
    let requestSlaDays: Int
    let statusProgressionSeconds: StatusProgression

    enum CodingKeys: String, CodingKey {
        case principals, notice, purposes
        case seedDataRequests = "seed_data_requests"
        case requestSlaDays = "request_sla_days"
        case statusProgressionSeconds = "status_progression_seconds"
    }

    /// Loads `demo-fixtures.json` from the app bundle.
    static func load() -> DemoFixtures {
        guard let url = Bundle(for: DemoBundleToken.self).url(forResource: "demo-fixtures", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let fixtures = try? JSONDecoder().decode(DemoFixtures.self, from: data)
        else {
            fatalError("demo-fixtures.json is missing from the app bundle or invalid")
        }
        return fixtures
    }
}

/// Anchor for `Bundle(for:)`, so the fixtures are found from the app and from the hosted unit tests.
private final class DemoBundleToken {}
