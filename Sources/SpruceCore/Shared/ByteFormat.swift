import Foundation

/// Formats byte counts the way Finder does (decimal units: 1 KB = 1000 bytes).
///
/// Implemented by hand so output is identical on macOS and Linux.
public enum ByteFormat {
    private static let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]

    /// "0 bytes", "512 bytes", "1.2 MB", "34.5 GB", "120 GB".
    public static func string(_ bytes: Int64) -> String {
        if bytes <= 0 { return "Zero KB" }
        if bytes < 1000 { return "\(bytes) bytes" }
        var value = Double(bytes)
        var unit = 0
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let rounded: String
        if value >= 100 {
            rounded = String(Int(value.rounded()))
        } else if value >= 10 {
            rounded = trimmed(String(format: "%.1f", value))
        } else {
            rounded = trimmed(String(format: "%.1f", value))
        }
        return "\(rounded) \(units[unit])"
    }

    /// Splits a formatted size into number and unit, for big hero numerals.
    public static func parts(_ bytes: Int64) -> (value: String, unit: String) {
        let s = string(bytes)
        if bytes <= 0 { return ("0", "KB") }
        guard let space = s.lastIndex(of: " ") else { return (s, "") }
        return (String(s[..<space]), String(s[s.index(after: space)...]))
    }

    private static func trimmed(_ s: String) -> String {
        s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

public enum CountFormat {
    /// "1 item", "1,204 items".
    public static func items(_ n: Int, singular: String = "item", plural: String? = nil) -> String {
        "\(grouped(n)) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// Thousands separators without relying on locale (stable in tests).
    public static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }
}

public enum DurationFormat {
    /// "3 min", "1 h 5 min", "12 s".
    public static func short(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s) s" }
        let m = s / 60
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let rem = m % 60
        return rem == 0 ? "\(h) h" : "\(h) h \(rem) min"
    }

    /// "today", "yesterday", "5 days ago", "3 months ago", "2 years ago".
    public static func relative(_ date: Date, now: Date = Date()) -> String {
        let days = Int(now.timeIntervalSince(date) / 86_400)
        if days <= 0 { return "today" }
        if days == 1 { return "yesterday" }
        if days < 31 { return "\(days) days ago" }
        let months = days / 30
        if months < 12 { return months == 1 ? "1 month ago" : "\(months) months ago" }
        let years = days / 365
        return years <= 1 ? "1 year ago" : "\(years) years ago"
    }
}
