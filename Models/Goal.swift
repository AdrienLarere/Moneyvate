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
    var completions: [String: Completion] = [:]
    
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
    
    enum CodingKeys: String, CodingKey {
        case id, userId, title, frequency, amountPerSuccess, startDate, endDate, totalAmount, verificationMethod, completions
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
         completions: [String: Completion] = [:]) {
        self.id = id
        self.userId = userId
        self.title = title
        self.frequency = frequency
        self.amountPerSuccess = amountPerSuccess
        self.startDate = startDate
        self.endDate = endDate
        self.totalAmount = totalAmount
        self.verificationMethod = verificationMethod
        self.completions = completions
    }
    
    var completionDates: [Date: Completion] {
        get {
            let dateFormatter = ISO8601DateFormatter()
            return Dictionary(uniqueKeysWithValues: completions.compactMap { key, value in
                guard let date = dateFormatter.date(from: key) else { return nil }
                return (date, value)
            })
        }
        set {
            let dateFormatter = ISO8601DateFormatter()
            completions = Dictionary(uniqueKeysWithValues: newValue.map { (dateFormatter.string(from: $0.key), $0.value) })
        }
    }
}

extension Goal {
    var numberOfDays: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }
    
    var requiredCompletions: Int {
        switch frequency {
        case .daily:
            return numberOfDays
        case .xDays:
            return min(numberOfDays, Int(totalAmount / amountPerSuccess))
        case .weekdays:
            return Calendar.current.weekdaySymbols.filter { !["Saturday", "Sunday"].contains($0) }.count
        case .weekends:
            return Calendar.current.weekdaySymbols.filter { ["Saturday", "Sunday"].contains($0) }.count
        }
    }
    
    var earnedAmount: Double {
        Double(completions.values.filter { $0.status == .refunded }.count) * amountPerSuccess
    }
}
