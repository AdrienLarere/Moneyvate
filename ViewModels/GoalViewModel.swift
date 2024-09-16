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
    
    func addGoal(title: String,
         frequency: Goal.Frequency,
         amountPerSuccess: Double,
         startDate: Date,
         endDate: Date,
         requiredCompletions: Int,
         verificationMethod: Goal.VerificationMethod,
         paymentIntentId: String?) {  // Add paymentIntentId as an optional parameter

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
           verificationMethod: verificationMethod,
           paymentIntentId: paymentIntentId) // Add paymentIntentId to the goal

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
            "refundedAt": newCompletion.refundedAt.map { Timestamp(date: $0) } as Any,
            "updatedAt": FieldValue.serverTimestamp()
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
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] querySnapshot, error in
                guard let snapshot = querySnapshot else {
                    print("Error fetching goals: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                if snapshot.metadata.isFromCache {
                    print("Data came from cache")
                } else {
                    print("Data came from server")
                }
                
                let documents = snapshot.documents
                
                if documents.isEmpty {
                    print("No documents found")
                    DispatchQueue.main.async {
                        self?.goals = []
                        self?.updateBalance()
                        self?.objectWillChange.send()
                    }
                    return
                }
                
                for document in documents {
                    print("Raw Firestore data for goal: \(document.data())")
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
                    
                    // Notify observers that goals have been updated
                    self?.objectWillChange.send()
                }
            }
    }
    
    func getGoal(withId id: String) -> Goal? {
        return goals.first { $0.id == id }
    }
    
    private func checkAndUpdateMissedCompletions() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let group = DispatchGroup()
        var batchOperations: [[String: Any]] = []
        
        for goal in goals {
            guard let goalId = goal.id else { continue }
            group.enter()
            
            let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
            
            goalRef.getDocument { (document, error) in
                defer { group.leave() }
                
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
                            batchOperations.append([
                                "ref": goalRef,
                                "data": ["completions.\(dateString)": completionData]
                            ])
                        }
                    }
                } else {
                    print("Document does not exist: \(goalId)")
                }
            }
        }
        
        group.notify(queue: .main) {
            if !batchOperations.isEmpty {
                let batch = self.db.batch()
                for operation in batchOperations {
                    if let ref = operation["ref"] as? DocumentReference,
                       let data = operation["data"] as? [String: Any] {
                        batch.updateData(data, forDocument: ref)
                    }
                }
                
                batch.commit { error in
                    if let error = error {
                        print("Error updating missed completions: \(error)")
                    } else {
                        print("Successfully updated missed completions for \(batchOperations.count) operations")
                    }
                }
            } else {
                print("No goals to update")
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
    
    func triggerRefund(for goal: Goal, on date: Date, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = Auth.auth().currentUser?.uid, let goalId = goal.id else {
            completion(.failure(NSError(domain: "GoalViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid user or goal ID"])))
            return
        }

        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
        let dateString = ISO8601DateFormatter().string(from: date)

        // First, check if the completion exists and is verified
        goalRef.getDocument { [weak self] (document, error) in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let document = document, document.exists,
                  let completions = document.data()?["completions"] as? [String: [String: Any]],
                  let completionData = completions[dateString],
                  let status = completionData["status"] as? String,
                  status == Completion.CompletionStatus.verified.rawValue else {
                completion(.failure(NSError(domain: "GoalViewModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Completion not found or not verified"])))
                return
            }

            // TODO: Implement actual refund logic here using Stripe API
            // For now, we'll simulate a successful refund

            // Update the completion status to refunded
            goalRef.updateData([
                "completions.\(dateString).status": Completion.CompletionStatus.refunded.rawValue,
                "completions.\(dateString).refundedAt": Timestamp(date: Date())
            ]) { error in
                if let error = error {
                    completion(.failure(error))
                } else {
                    // Update the local goal object
                    if let index = self?.goals.firstIndex(where: { $0.id == goalId }) {
                        self?.goals[index].completions[dateString]?.status = .refunded
                        self?.goals[index].completions[dateString]?.refundedAt = Date()
                        self?.updateBalance()
                        self?.objectWillChange.send()
                    }
                    completion(.success(()))
                }
            }
        }
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
