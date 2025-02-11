import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String? // user’s UID
    var email: String
    var currency: String
    var isAdmin: Bool
    var firstName: String?
    var lastName: String?

    init(id: String? = nil,
         email: String,
         currency: String = "USD",
         isAdmin: Bool = false,
         firstName: String? = nil,
         lastName: String? = nil)
    {
        self.id = id
        self.email = email
        self.currency = currency
        self.isAdmin = isAdmin
        self.firstName = firstName
        self.lastName = lastName
    }
}
