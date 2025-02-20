import Foundation
import FirebaseFirestore

struct UserProfile: Codable, Identifiable {
    @DocumentID var id: String? // user’s UID
    var email: String
    var currency: String
    var isAdmin: Bool
    var firstName: String?
    var lastName: String?
    var themeMode: String?  // "system", "light", or "dark"

    init(id: String? = nil,
         email: String,
         currency: String = "USD",
         isAdmin: Bool = false,
         firstName: String? = nil,
         lastName: String? = nil,
         themeMode: String? = "system")  // Default to system
    {
        self.id = id
        self.email = email
        self.currency = currency
        self.isAdmin = isAdmin
        self.firstName = firstName
        self.lastName = lastName
        self.themeMode = themeMode
    }
}
