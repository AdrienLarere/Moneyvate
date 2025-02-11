import Foundation
import FirebaseFirestore

struct Goal: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String?
    var title: String
    var frequency: Frequency
    var amountPerSuccess: Double
    var startDate: Date
    var endDate: Date
    var totalAmount: Double
    var verificationMethod: VerificationMethod
    var paymentIntentId: String?
    var currency: String?
    var manuallyRefunded: Bool?
    var isDeleted: Bool?      // true if the goal is deleted
    var deletionDate: Date?     // the date when the goal was deleted
    
    // NEW: Only applicable when frequency == .xDays
    var selectedXDays: Int?
    
    var startDateLocalString: String {
        convertUTCToLocalDateString(date: startDate)
    }
    var endDateLocalString: String {
        convertUTCToLocalDateString(date: endDate)
    }
    
    private func convertUTCToLocalDateString(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC source
        guard let utcDate = formatter.date(from: formatter.string(from: date)) else {
            return formatter.string(from: date)
        }
        
        formatter.timeZone = TimeZone.current // Convert to local
        return formatter.string(from: utcDate)
    }

    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily = "Every day"
        case xDays = "X days over the period"
        case weekdays = "Weekdays only"
        case weekends = "Weekends only"
        
        var id: String { self.rawValue }
    }
    
    enum VerificationMethod: String, Codable, CaseIterable, Identifiable {
        case selfVerify = "Self Verify"
        case photoVerification = "Photo Verification"
        
        var id: String { self.rawValue }
    }
    
    // Only list the fields that actually exist on the Goal doc
    enum CodingKeys: String, CodingKey {
        case id, userId, title, frequency, amountPerSuccess, startDate, endDate,
             totalAmount, verificationMethod, paymentIntentId, currency, selectedXDays, manuallyRefunded, isDeleted, deletionDate
    }

    init(id: String? = nil,
         userId: String,
         title: String,
         frequency: Frequency,
         amountPerSuccess: Double,
         startDate: Date,
         endDate: Date,
         totalAmount: Double,
         verificationMethod: VerificationMethod,
         currency: String?,
         paymentIntentId: String? = nil,
         selectedXDays: Int? = nil,
         manuallyRefunded: Bool = false,
         isDeleted: Bool? = false,
         deletionDate: Date? = nil) {
        self.id = id
        self.userId = userId
        self.title = title
        self.frequency = frequency
        self.amountPerSuccess = amountPerSuccess
        self.startDate = startDate
        self.endDate = endDate
        self.totalAmount = totalAmount
        self.verificationMethod = verificationMethod
        self.currency = currency
        self.paymentIntentId = paymentIntentId
        self.selectedXDays = selectedXDays
        self.manuallyRefunded = manuallyRefunded
        self.isDeleted = isDeleted
        self.deletionDate = deletionDate
    }
}

// MARK: - Computed Properties
extension Goal {
    /// The total count of days from start to end
    var numberOfDays: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return days + 1
    }
    
    /// How many completions are required by frequency
    var requiredCompletions: Int {
        switch frequency {
        case .daily:
            return numberOfDays

        case .xDays:
            if let selected = selectedXDays {
                return selected
            } else {
                // Fallback: use the computed logic.
                return min(numberOfDays, Int(totalAmount / amountPerSuccess))
            }

        case .weekdays:
            // Actually loop from startDate...endDate and count M–F
            return Goal.countWeekdaysBetween(startDate, endDate)

        case .weekends:
            // Actually loop from startDate...endDate and count Sat/Sun
            return Goal.countWeekendsBetween(startDate, endDate)
        }
    }
    
    private static func countWeekdaysBetween(_ start: Date, _ end: Date) -> Int {
        let calendar = Calendar.current
        var count = 0
        
        var day = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        
        while day <= endDay {
            if !calendar.isDateInWeekend(day) {
                count += 1
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }

    private static func countWeekendsBetween(_ start: Date, _ end: Date) -> Int {
        let calendar = Calendar.current
        var count = 0

        var day = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        while day <= endDay {
            if calendar.isDateInWeekend(day) {
                count += 1
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return count
    }
    
}
