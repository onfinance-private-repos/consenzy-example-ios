// Copyright 2026 OnFinance. SPDX-License-Identifier: Apache-2.0

import Foundation

/// ISO-8601 / RFC 3339 timestamps as the API emits them, e.g. `2026-10-22T13:55:13.663200Z`
/// or `2026-10-22T19:25:13.6632+05:30`.
///
/// Implemented arithmetically rather than with `ISO8601DateFormatter`, whose handling of
/// more than three fractional digits differs between OS versions and Linux Foundation,
/// and which is not `Sendable`.
public enum ISO8601 {
    /// Parses `YYYY-MM-DDTHH:MM:SS[.fraction][Z|±HH:MM|±HHMM]`. A missing offset is read as UTC.
    public static func parse(_ string: String) -> Date? {
        let s = Array(string.utf8)
        var i = 0

        func digits(_ count: Int) -> Int? {
            guard i + count <= s.count else { return nil }
            var value = 0
            for _ in 0..<count {
                let c = s[i]
                guard c >= 48 && c <= 57 else { return nil }
                value = value * 10 + Int(c - 48)
                i += 1
            }
            return value
        }
        func expect(_ chars: UInt8...) -> Bool {
            guard i < s.count, chars.contains(s[i]) else { return false }
            i += 1
            return true
        }

        guard let year = digits(4), expect(45), let month = digits(2), expect(45), let day = digits(2),
              expect(84, 116, 32), // 'T', 't' or ' '
              let hour = digits(2), expect(58), let minute = digits(2), expect(58), let second = digits(2)
        else { return nil }
        guard (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second <= 60 else { return nil }

        var fraction = 0.0
        if i < s.count, s[i] == 46 || s[i] == 44 { // '.' or ','
            i += 1
            var scale = 0.1
            let start = i
            while i < s.count, s[i] >= 48 && s[i] <= 57 {
                fraction += Double(s[i] - 48) * scale
                scale /= 10
                i += 1
            }
            guard i > start else { return nil }
        }

        var offsetSeconds = 0
        if i < s.count {
            if s[i] == 90 || s[i] == 122 { // 'Z' / 'z'
                i += 1
            } else if s[i] == 43 || s[i] == 45 { // '+' / '-'
                let sign = s[i] == 45 ? -1 : 1
                i += 1
                guard let oh = digits(2) else { return nil }
                _ = expect(58)
                guard let om = digits(2), oh < 24, om < 60 else { return nil }
                offsetSeconds = sign * (oh * 3600 + om * 60)
            } else {
                return nil
            }
        }
        guard i == s.count else { return nil }

        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }

    /// Formats a date in UTC with millisecond precision, e.g. `2026-10-22T13:55:13.663Z`.
    public static func format(_ date: Date) -> String {
        let totalMillis = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        var seconds = totalMillis / 1000
        var millis = totalMillis % 1000
        if millis < 0 { millis += 1000; seconds -= 1 }
        var days = seconds / 86_400
        var secOfDay = seconds % 86_400
        if secOfDay < 0 { secOfDay += 86_400; days -= 1 }
        let (y, m, d) = civilFromDays(Int(days))
        return String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
            y, m, d, Int(secOfDay / 3600), Int(secOfDay % 3600 / 60), Int(secOfDay % 60), Int(millis)
        )
    }

    // Howard Hinnant's days_from_civil / civil_from_days (proleptic Gregorian).
    static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (m <= 2 ? 1 : 0), m, d)
    }
}

extension JSONDecoder {
    /// A decoder configured for Consent Data Master responses.
    public static func consentDataMaster() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601.parse(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date: \(raw)")
            }
            return date
        }
        return decoder
    }
}

extension JSONEncoder {
    /// An encoder configured for Consent Data Master requests.
    public static func consentDataMaster() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.format(date))
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
