import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String? // This will be the user's UID
    var email: String
    var currency: String
    var isAdmin: Bool  // ← New field

    init(id: String? = nil, email: String, currency: String = "USD", isAdmin: Bool = false) {
        self.id = id
        self.email = email
        self.currency = currency
        self.isAdmin = isAdmin
    }
}
