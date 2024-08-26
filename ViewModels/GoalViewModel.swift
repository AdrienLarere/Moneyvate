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
        let newGoal = Goal(title: title,
                           frequency: frequency,
                           amountPerSuccess: amountPerSuccess,
                           startDate: startDate,
                           endDate: endDate,
                           totalAmount: totalAmount,
                           verificationMethod: verificationMethod)
        
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        do {
            try db.collection("users").document(userId).collection("goals").addDocument(from: newGoal)
        } catch {
            print("Error adding goal: \(error.localizedDescription)")
        }
    }
    
    func toggleGoalCompletion(goal: Goal, date: Date) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        let goalRef = db.collection("users").document(userId).collection("goals").document(goal.id)
        
        goalRef.updateData([
            "completions.\(ISO8601DateFormatter().string(from: date))": !(goal.completionDates[date] ?? false)
        ]) { error in
            if let error = error {
                print("Error updating goal completion: \(error.localizedDescription)")
            }
        }
    }
    
    func fetchGoals() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        listenerRegistration = db.collection("users").document(userId).collection("goals")
        .addSnapshotListener { [weak self] querySnapshot, error in
            guard let documents = querySnapshot?.documents else {
                print("Error fetching documents: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            self?.goals = documents.compactMap { queryDocumentSnapshot -> Goal? in
                try? queryDocumentSnapshot.data(as: Goal.self)
            }
            
            self?.updateBalance()
        }
    }
    
    func clearGoals() {
        goals = []
        balance = 0
        // Any other cleanup needed
    }
    
    private func updateBalance() {
        balance = goals.reduce(0) { $0 + $1.earnedAmount - $1.totalAmount }
    }
    
    deinit {
        listenerRegistration?.remove()
    }
}
