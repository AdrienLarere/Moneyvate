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
    
    func addCompletion(for goal: Goal, on date: Date, verificationPhotoUrl: String? = nil) {
        print("Goal before update: \(goal)")
        guard let userId = Auth.auth().currentUser?.uid, let goalId = goal.id else { return }
        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)

        let newCompletion = Completion(
            goalId: goalId,
            date: date,
            status: goal.verificationMethod == .selfVerify ? .verified : .pendingVerification,
            verificationPhotoUrl: verificationPhotoUrl,
            verifiedAt: goal.verificationMethod == .selfVerify ? date : nil
        )

        let completionData: [String: Any] = [
            "goalId": newCompletion.goalId,
            "date": Timestamp(date: newCompletion.date),
            "status": newCompletion.status.rawValue,
            "verificationPhotoUrl": newCompletion.verificationPhotoUrl as Any,
            "verifiedAt": newCompletion.verifiedAt.map { Timestamp(date: $0) } as Any,
            "refundedAt": newCompletion.refundedAt.map { Timestamp(date: $0) } as Any
        ]

        goalRef.updateData([
            "completions.\(ISO8601DateFormatter().string(from: date))": completionData
        ]) { [weak self] error in
            if let error = error {
                print("Error adding completion: \(error.localizedDescription)")
            } else {
                print("Completion added successfully")
                print("Updated goal: \(goal.title), Date: \(date), Status: \(newCompletion.status)")
                
                // Update the local goals array
                DispatchQueue.main.async {
                    if let index = self?.goals.firstIndex(where: { $0.id == goal.id }) {
                        self?.goals[index].completions[ISO8601DateFormatter().string(from: date)] = newCompletion
                        self?.updateBalance()
                        self?.objectWillChange.send()
                    }
                }
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
                
                let newGoals = documents.compactMap { queryDocumentSnapshot -> Goal? in
                    do {
                        return try queryDocumentSnapshot.data(as: Goal.self)
                    } catch {
                        print("Error decoding goal: \(error.localizedDescription)")
                        return nil
                    }
                }
                
                DispatchQueue.main.async {
                    let oldGoalIds = Set(self?.goals.compactMap { $0.id } ?? [])
                    let newGoalIds = Set(newGoals.compactMap { $0.id })
                    
                    self?.goals = newGoals
                    self?.updateBalance()
                    
                    if oldGoalIds != newGoalIds {
                        self?.checkAndUpdateMissedCompletions()
                    }
                }
            }
    }
    
    func getGoal(withId id: String) -> Goal? {
        return goals.first { $0.id == id }
    }
    
    private func checkAndUpdateMissedCompletions() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let batch = db.batch()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var updatedGoals = [String]()
        
        for goal in goals {
            guard let goalId = goal.id else { continue }
            let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
            
            goalRef.getDocument { (document, error) in
                if let document = document, document.exists {
                    for date in self.dateRange(from: goal.startDate, to: min(today, goal.endDate)) {
                        let dateString = ISO8601DateFormatter().string(from: date)
                        if goal.completions[dateString] == nil {
                            let missedCompletion = Completion(goalId: goalId, date: date, status: .missed)
                            let completionData: [String: Any] = [
                                "goalId": missedCompletion.goalId,
                                "date": Timestamp(date: missedCompletion.date),
                                "status": missedCompletion.status.rawValue
                            ]
                            batch.updateData(["completions.\(dateString)": completionData], forDocument: goalRef)
                        }
                    }
                    updatedGoals.append(goalId)
                } else {
                    print("Document does not exist: \(goalId)")
                }
                
                if goalId == self.goals.last?.id {
                    if !updatedGoals.isEmpty {
                        batch.commit { error in
                            if let error = error {
                                print("Error updating missed completions: \(error)")
                            } else {
                                print("Successfully updated missed completions for \(updatedGoals.count) goals")
                            }
                        }
                    } else {
                        print("No goals to update")
                    }
                }
            }
        }
    }
    
    // Custom function to generate date range
    private func dateRange(from: Date, to: Date) -> [Date] {
       var dates: [Date] = []
       var date = from

       while date <= to {
           dates.append(date)
           guard let newDate = Calendar.current.date(byAdding: .day, value: 1, to: date) else { break }
           date = newDate
       }

       return dates
    }
    
    func updateGoal(_ updatedGoal: Goal) {
        if let index = goals.firstIndex(where: { $0.id == updatedGoal.id }) {
            goals[index] = updatedGoal
            updateBalance()
            objectWillChange.send()  // Explicitly notify observers of the change
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
