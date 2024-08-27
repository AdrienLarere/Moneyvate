import Foundation
import FirebaseFirestore
import FirebaseAuth

class GoalViewModel: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var balance: Double = 0
    
    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    init() {
        fetchGoals()
    }
    
    func addGoal(title: String, frequency: Goal.Frequency, amountPerSuccess: Double, startDate: Date, endDate: Date, requiredCompletions: Int, verificationMethod: Goal.VerificationMethod) {
        let totalAmount = Double(requiredCompletions) * amountPerSuccess
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let newGoal = Goal(id: nil,
                           userId: userId,
                           title: title,
                           frequency: frequency,
                           amountPerSuccess: amountPerSuccess,
                           startDate: startDate,
                           endDate: endDate,
                           totalAmount: totalAmount,
                           verificationMethod: verificationMethod)
        
        do {
            try db.collection("users").document(userId).collection("goals").addDocument(from: newGoal)
        } catch {
            print("Error adding goal: \(error.localizedDescription)")
        }
    }
    
    func addCompletion(for goal: Goal, on date: Date) {
        guard let userId = Auth.auth().currentUser?.uid, let goalId = goal.id else { return }
        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
        
        let newCompletion = Completion(goalId: goalId,
                                       date: date,
                                       status: goal.verificationMethod == .selfVerify ? .verified : .pendingVerification)
        
        goalRef.updateData([
            "completions.\(ISO8601DateFormatter().string(from: date))": newCompletion
        ]) { error in
            if let error = error {
                print("Error adding completion: \(error.localizedDescription)")
            }
        }
    }
    
    func updateCompletionStatus(for goal: Goal, on date: Date, newStatus: Completion.CompletionStatus) {
        guard let userId = Auth.auth().currentUser?.uid, let goalId = goal.id else { return }
        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
        
        goalRef.updateData([
            "completions.\(ISO8601DateFormatter().string(from: date)).status": newStatus.rawValue
        ]) { error in
            if let error = error {
                print("Error updating completion status: \(error.localizedDescription)")
            }
        }
    }
    
    func fetchGoals() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        print("Fetching goals for user: \(userId)")
        
        listenerRegistration = db.collection("users").document(userId).collection("goals")
        .addSnapshotListener { [weak self] querySnapshot, error in
            if let error = error {
                print("Error fetching documents: \(error.localizedDescription)")
                return
            }
            
            guard let documents = querySnapshot?.documents else {
                print("No documents found")
                return
            }
            
            print("Found \(documents.count) documents")
            
            self?.goals = documents.compactMap { queryDocumentSnapshot -> Goal? in
                do {
                    let goal = try queryDocumentSnapshot.data(as: Goal.self)
                    print("Successfully decoded goal: \(goal.title)")
                    return goal
                } catch {
                    print("Error decoding goal (document ID: \(queryDocumentSnapshot.documentID)): \(error.localizedDescription)")
                    return nil
                }
            }
            
            print("Decoded \(self?.goals.count ?? 0) goals")
            self?.updateBalance()
        }
    }
    
    func clearGoals() {
        goals = []
        balance = 0
        listenerRegistration?.remove()
    }
    
    private func updateBalance() {
        balance = goals.reduce(0) { $0 + $1.earnedAmount - $1.totalAmount }
    }
    
    deinit {
        listenerRegistration?.remove()
    }
}
