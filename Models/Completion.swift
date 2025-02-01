import Foundation
import FirebaseFirestore

struct Completion: Identifiable, Codable {
    @DocumentID var id: String?
    var goalId: String
    var date: Date
    var dateString: String?
    var status: CompletionStatus
    var verificationPhotoUrl: String?
    var verifiedAt: Date?
    var refundedAt: Date?
    var refundError: String?
    var explanation: String?

    enum CompletionStatus: String, Codable {
        case nonSubmitted
        case pendingVerification
        case verified
        case refunded
        case refundFailed
        case rejected
        case missed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case goalId
        case date
        case dateString
        case status
        case verificationPhotoUrl
        case verifiedAt
        case refundedAt
        case refundError
        case explanation
    }
}
