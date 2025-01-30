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
             totalAmount, verificationMethod, paymentIntentId, currency
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
         paymentIntentId: String? = nil) {
        
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
    }
}

// MARK: - Computed Properties
extension Goal {
    /// The total count of days from start to end
    var numberOfDays: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return days + 1
    }
    
    /// How many completions are required by frequency
    var requiredCompletions: Int {
        switch frequency {
        case .daily:
            return numberOfDays

        case .xDays:
            // However you define "X days," e.g. totalAmount ÷ amountPerSuccess:
            return min(numberOfDays, Int(totalAmount / amountPerSuccess))

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
