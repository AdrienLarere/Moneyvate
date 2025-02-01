import Firebase
import Combine
import Foundation
import FirebaseFirestore
import FirebaseAuth

class AdminViewModel: ObservableObject {
    @Published var pendingCompletions: [(completion: Completion, ref: DocumentReference)] = []
    @Published var rejectedCompletions: [(completion: Completion, ref: DocumentReference)] = []
    
    // NEW: All completions (verified/refunded) from goals that require photo upload
    @Published var verifiedPhotoCompletions: [(completion: Completion, ref: DocumentReference)] = []
    
    @Published var errorMessage: String?
    @Published var isAdmin = false
    
    private var db = Firestore.firestore()
    
    // Existing listeners
    private var pendingListener: ListenerRegistration?
    private var rejectedListener: ListenerRegistration?
    private var verifiedListener: ListenerRegistration?
    
    // NEW: Listeners for goals and their completions
    private var photoGoalsListener: ListenerRegistration?
    private var photoGoalCompletionListeners: [ListenerRegistration] = []

    init() {
        checkAdminStatus()
    }
    
    private func checkAdminStatus() {
        guard let userId = Auth.auth().currentUser?.uid else {
            errorMessage = "Not authenticated"
            return
        }
        
        db.collection("users").document(userId)
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let data = snapshot?.data(),
                      let isAdmin = data["isAdmin"] as? Bool else {
                    self?.errorMessage = "Admin privileges not found"
                    return
                }
                
                self?.isAdmin = isAdmin
                if isAdmin {
                    self?.fetchPendingCompletions()
                    self?.fetchRejectedCompletions()
                    self?.fetchVerifiedPhotoCompletions()  // ← NEW
                }
            }
    }
    
    private func fetchPendingCompletions() {
        pendingListener = db.collectionGroup("completions")
            .whereField("status", isEqualTo: Completion.CompletionStatus.pendingVerification.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching pending completions: \(error)")
                    return
                }
                self?.pendingCompletions = snapshot?.documents.compactMap { doc in
                    guard let completion = try? doc.data(as: Completion.self) else { return nil }
                    return (completion, doc.reference)
                } ?? []
            }
    }
    
    private func fetchRejectedCompletions() {
        rejectedListener = db.collectionGroup("completions")
            .whereField("status", isEqualTo: Completion.CompletionStatus.rejected.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching rejected completions: \(error)")
                    return
                }
                self?.rejectedCompletions = snapshot?.documents.compactMap { doc in
                    guard let completion = try? doc.data(as: Completion.self) else { return nil }
                    return (completion, doc.reference)
                } ?? []
            }
    }

    // MARK: - Fetch verified/refunded completions for goals with "photoVerification"
// NEW: fetch all completions with status = verified OR refunded,
    // and only keep those with a non-nil verificationPhotoUrl.
    private func fetchVerifiedPhotoCompletions() {
        verifiedListener = db.collectionGroup("completions")
            .whereField("status", in: [
                Completion.CompletionStatus.verified.rawValue,
                Completion.CompletionStatus.refunded.rawValue
            ])
            .addSnapshotListener { [weak self] snapshot, error in
                if let error = error {
                    print("Error fetching verified/refunded completions: \(error)")
                    return
                }
                
                self?.verifiedPhotoCompletions = snapshot?.documents.compactMap { doc in
                    guard let completion = try? doc.data(as: Completion.self) else { return nil }
                    // Filter out if no photo URL
                    guard let _ = completion.verificationPhotoUrl else {
                        return nil
                    }
                    return (completion, doc.reference)
                } ?? []
            }
    }

    /// Helper to merge/replace completions for a specific goal in `photoVerifiedCompletions`.
    private func updatePhotoVerifiedCompletions(
        forGoalId goalId: String,
        completions: [(Completion, DocumentReference)]
    ) {
        // Remove existing completions for this goal
        verifiedPhotoCompletions.removeAll { pair in
            pair.completion.goalId == goalId
        }
        // Append the new ones
        verifiedPhotoCompletions.append(contentsOf: completions)
    }

    // MARK: - Approve / Reject / Undo
    func approveSubmission(_ ref: DocumentReference) {
        ref.updateData([
            "status": Completion.CompletionStatus.verified.rawValue,
            "verifiedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("Approval error: \(error.localizedDescription)")
            }
        }
    }

    func rejectSubmission(_ ref: DocumentReference) {
        ref.updateData([
            "status": Completion.CompletionStatus.rejected.rawValue,
            "verifiedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("Rejection error: \(error.localizedDescription)")
            }
        }
    }

    func undoRejection(_ ref: DocumentReference) {
        ref.updateData([
            "status": Completion.CompletionStatus.pendingVerification.rawValue,
            "verifiedAt": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("Undo rejection error: \(error.localizedDescription)")
            }
        }
    }
}
