import Foundation
import FirebaseFirestore

struct UserInfo: Identifiable, Codable {
    @DocumentID var id: String?
    var email: String
    var installs: [Date]
    var deletions: [Date]
    var isInstalled: Bool
    var blockedUntil: Date?  // new field

    init(id: String? = nil,
         email: String,
         installs: [Date] = [],
         deletions: [Date] = [],
         isInstalled: Bool = true,
         blockedUntil: Date? = nil)
    {
        self.id = id
        self.email = email
        self.installs = installs
        self.deletions = deletions
        self.isInstalled = isInstalled
        self.blockedUntil = blockedUntil
    }
}

