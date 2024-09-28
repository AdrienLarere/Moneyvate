// DateFormatterHelper.swift

import Foundation

struct DateFormatterHelper {
    // Shared date formatter for dates without time components
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd" // Only date components
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // Use UTC to avoid time zone issues
        formatter.locale = Locale(identifier: "en_US_POSIX") // Ensure consistent locale
        return formatter
    }()
}
