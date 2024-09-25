import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String? // This will be the user's UID
    var email: String
    var currency: String // e.g., "USD", "GBP", "EUR"
    
    init(id: String? = nil, email: String, currency: String = "USD") {
        self.id = id
        self.email = email
        self.currency = currency
    }
}
