import Foundation
import OnFinanceConsenzy
import SwiftUI

/// User-facing text for errors from the SDK and from the session server.
enum ErrorText {
    static func describe(_ error: Error) -> String {
        switch error {
        case let error as ConsentAPIError:
            if error.isGuardianRequired { return "A parent or guardian must give this consent. (\(error.status): \(error.message))" }
            if let capability = error.missingCapability { return "This session lacks the \(capability.rawValue) capability." }
            return "Consenzy answered \(error.status): \(error.message)"
        case let error as ConsentClientError:
            return error.description
        case let error as SessionServerError:
            return error.errorDescription ?? "Session server error"
        default:
            return error.localizedDescription
        }
    }
}

extension Date {
    var shortDate: String { formatted(date: .abbreviated, time: .omitted) }
    var shortDateTime: String { formatted(date: .abbreviated, time: .shortened) }
}

extension JSONValue {
    /// A compact display string for scalar JSON values.
    var displayText: String {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array, .object:
            let data = (try? JSONEncoder.consentDataMaster().encode(self)) ?? Data()
            return String(data: data, encoding: .utf8) ?? ""
        }
    }
}

/// A label/value row for evidence and metadata.
struct FieldRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.callout.monospaced()).textSelection(.enabled)
        }
    }
}
