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
    var refundError: String? // New field to store refund error messages

    enum CompletionStatus: String, Codable {
        case nonSubmitted
        case pendingVerification
        case verified
        case refunded
        case refundFailed // New status for refund failure
        case rejected
        case missed
    }

    // Remove CodingKeys and custom init/encode methods to use automatic synthesis
    /*
    enum CodingKeys: String, CodingKey { ... }

    init(from decoder: Decoder) throws { ... }

    func encode(to encoder: Encoder) throws { ... }
    */
}
