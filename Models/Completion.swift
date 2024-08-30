import Foundation
import FirebaseFirestore

struct Completion: Identifiable, Codable {
    @DocumentID var id: String?
    var goalId: String
    var date: Date
    var status: CompletionStatus
    var verificationPhotoUrl: String?
    var verifiedAt: Date?
    var refundedAt: Date?
    
    enum CompletionStatus: String, Codable {
        case pendingVerification
        case verified
        case refunded
        case rejected
        case missed
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case goalId
        case date
        case status
        case verificationPhotoUrl
        case verifiedAt
        case refundedAt
    }
    
    init(id: String? = nil, goalId: String, date: Date, status: CompletionStatus, verificationPhotoUrl: String? = nil, verifiedAt: Date? = nil, refundedAt: Date? = nil) {
        self.id = id
        self.goalId = goalId
        self.date = date
        self.status = status
        self.verificationPhotoUrl = verificationPhotoUrl
        self.verifiedAt = verifiedAt
        self.refundedAt = refundedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        goalId = try container.decode(String.self, forKey: .goalId)
        date = try container.decode(Date.self, forKey: .date)
        status = try container.decode(CompletionStatus.self, forKey: .status)
        verificationPhotoUrl = try container.decodeIfPresent(String.self, forKey: .verificationPhotoUrl)
        verifiedAt = try container.decodeIfPresent(Date.self, forKey: .verifiedAt)
        refundedAt = try container.decodeIfPresent(Date.self, forKey: .refundedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(goalId, forKey: .goalId)
        try container.encode(date, forKey: .date)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(verificationPhotoUrl, forKey: .verificationPhotoUrl)
        try container.encodeIfPresent(verifiedAt, forKey: .verifiedAt)
        try container.encodeIfPresent(refundedAt, forKey: .refundedAt)
    }
}
