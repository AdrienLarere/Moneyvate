import Foundation
import FirebaseFirestore
import FirebaseAuth

class GoalViewModel: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var balance: Double = 0

    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    var totalEarnedBack: Double {
        goals.reduce(0) { $0 + $1.earnedAmount }
    }

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
         currency: String, // Add currency parameter
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
           currency: currency, // Add currency parameter
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
        
        let dateString = DateFormatterHelper.shared.string(from: date) // Use consistent date string

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
            "completions.\(dateString)": completionData
        ]) { [weak self] error in
            if let error = error {
                print("Error adding completion: \(error.localizedDescription)")
            } else {
                print("Completion added successfully")
                print("Updated goal: \(goal.title), Date: \(date), Status: \(newCompletion.status)")
                
                // Update the local goals array
                DispatchQueue.main.async {
                    if let index = self?.goals.firstIndex(where: { $0.id == goal.id }) {
                        self?.goals[index].completions[dateString] = newCompletion
                        self?.updateBalance()
                        self?.objectWillChange.send()
                    }
                }
            }
        }
    }
    
    func updateCompletionStatus(for goal: Goal, on date: Date, newStatus: Completion.CompletionStatus) {
        guard let userId = Auth.auth().currentUser?.uid, let goalId = goal.id else { return }
        
        let dateString = DateFormatterHelper.shared.string(from: date) // Use consistent date string
        
        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
        
        goalRef.updateData([
            "completions.\(dateString).status": newStatus.rawValue
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
                
                let newGoals = documents.compactMap { queryDocumentSnapshot -> Goal? in
                    do {
                        return try queryDocumentSnapshot.data(as: Goal.self)
                    } catch {
                        print("Error decoding goal: \(error.localizedDescription)")
                        return nil
                    }
                }
                
                DispatchQueue.main.async {
                    self?.goals = newGoals
                    self?.updateBalance()

                    // Debug: Print currencies of all goals
                    for goal in newGoals {
                        print("Goal ID: \(goal.id ?? "unknown"), Currency: \(goal.currency ?? "nil")")
                    }

                    self?.objectWillChange.send()
                }
            }
    }
    
    func getGoal(withId id: String) -> Goal? {
        return goals.first { $0.id == id }
    }
    
    func updateGoalInDatabase(_ goal: Goal) {
        guard let userId = Auth.auth().currentUser?.uid, let goalId = goal.id else { return }
        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)

        do {
            try goalRef.setData(from: goal, merge: true) // Use merge to update only changed fields
        } catch {
            print("Error updating goal: \(error.localizedDescription)")
        }
    }
    
    func checkAndUpdateMissedCompletions(for goal: Goal, completion: @escaping () -> Void) {
        guard let userId = Auth.auth().currentUser?.uid, let goalId = goal.id else { return }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
        
        goalRef.getDocument { [weak self] (documentSnapshot, error) in
            if let error = error {
                print("Error fetching goal document: \(error.localizedDescription)")
                completion()
                return
            }
            
            guard let document = documentSnapshot, document.exists else {
                print("Goal document does not exist")
                completion()
                return
            }
            
            // Fetch the latest completions from the document
            guard let data = document.data(),
                  let completionsData = data["completions"] as? [String: [String: Any]] else {
                print("No completions found in document")
                completion()
                return
            }
            
            var completions = goal.completions
            for (dateString, _) in completionsData {
                if completions[dateString] == nil {
                    // Parse the completion data and add it to the local completions dictionary
                    if let completionData = completionsData[dateString],
                       let completion = Completion(from: completionData) {
                        completions[dateString] = completion
                    }
                }
            }
            
            // Determine which dates are missed
            var batchUpdates: [String: Any] = [:]
            
            // Normalize dates
            let goalStartDate = calendar.startOfDay(for: goal.startDate)
            let goalEndDate = calendar.startOfDay(for: goal.endDate)
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            let endDateForMissed = min(yesterday, goalEndDate)
            
            // Only proceed if goalStartDate <= endDateForMissed
            if goalStartDate <= endDateForMissed {
                for date in self?.dateRange(from: goalStartDate, to: endDateForMissed) ?? [] {
                    let dateString = DateFormatterHelper.shared.string(from: date)
                    if completions[dateString] == nil {
                        // No completion exists for this date; mark as missed
                        let missedCompletion = Completion(goalId: goalId, date: date, status: .missed)
                        let completionData: [String: Any] = [
                            "goalId": missedCompletion.goalId,
                            "date": Timestamp(date: missedCompletion.date),
                            "status": missedCompletion.status.rawValue
                        ]
                        batchUpdates["completions.\(dateString)"] = completionData
                        // Update the local completions dictionary
                        completions[dateString] = missedCompletion
                    }
                }
            }
            
            if !batchUpdates.isEmpty {
                // Update the database
                goalRef.updateData(batchUpdates) { error in
                    if let error = error {
                        print("Error updating missed completions: \(error.localizedDescription)")
                    } else {
                        print("Missed completions updated successfully")
                        // Update the local goal object
                        if let index = self?.goals.firstIndex(where: { $0.id == goalId }) {
                            self?.goals[index].completions = completions
                            self?.objectWillChange.send()
                        }
                    }
                    completion()
                }
            } else {
                print("No missed completions to update for goal \(goalId)")
                completion()
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
        guard let userId = Auth.auth().currentUser?.uid, let goalId = goal.id, let paymentIntentId = goal.paymentIntentId else {
            completion(.failure(NSError(domain: "GoalViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid user, goal ID, or payment intent ID"])))
            return
        }

        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
        let dateString = DateFormatterHelper.shared.string(from: date) // Use consistent date string

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

            // Implement actual refund logic here using Stripe API
            self?.processRefund(paymentIntentId: paymentIntentId, amount: Int(goal.amountPerSuccess * 100)) { result in
                switch result {
                case .success:
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
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    private func processRefund(paymentIntentId: String, amount: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(AppConfig.serverURL)/refund-payment") else {
            print("Invalid server URL")
            completion(.failure(NSError(domain: "GoalViewModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])))
            return
        }

        print("Initiating refund process for paymentIntentId: \(paymentIntentId), amount: \(amount)")

        // Get the ID token asynchronously
        Auth.auth().currentUser?.getIDToken { token, error in
            if let error = error {
                print("Error getting ID token: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let token = token else {
                print("Failed to get authentication token")
                completion(.failure(NSError(domain: "GoalViewModel", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to get authentication token"])))
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let body: [String: Any] = [
                "paymentIntentId": paymentIntentId,
                "amount": amount
            ]

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                print("Request body: \(body)")
            } catch {
                print("Error creating request body: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse {
                    print("HTTP response status code: \(httpResponse.statusCode)")
                }

                guard let data = data else {
                    print("No data received from server")
                    completion(.failure(NSError(domain: "GoalViewModel", code: 4, userInfo: [NSLocalizedDescriptionKey: "No data received from server"])))
                    return
                }

                // Log the raw response data
                if let rawResponse = String(data: data, encoding: .utf8) {
                    print("Raw server response: \(rawResponse)")
                } else {
                    print("Unable to convert response data to string")
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("Parsed server response: \(json)")
                        if let success = json["success"] as? Bool, success {
                            print("Refund successful")
                            completion(.success(()))
                        } else {
                            print("Refund failed")
                            completion(.failure(NSError(domain: "GoalViewModel", code: 5, userInfo: [NSLocalizedDescriptionKey: "Refund failed"])))
                        }
                    } else {
                        print("Invalid JSON response")
                        completion(.failure(NSError(domain: "GoalViewModel", code: 7, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])))
                    }
                } catch {
                    print("Error parsing server response: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }.resume()
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

// Helper function to parse Completion from Firestore data
extension Completion {
    init?(from data: [String: Any]) {
        guard let goalId = data["goalId"] as? String,
              let timestamp = data["date"] as? Timestamp,
              let statusRaw = data["status"] as? String,
              let status = CompletionStatus(rawValue: statusRaw) else {
            return nil
        }
        
        self.goalId = goalId
        self.date = timestamp.dateValue()
        self.status = status
        self.verificationPhotoUrl = data["verificationPhotoUrl"] as? String
        self.verifiedAt = (data["verifiedAt"] as? Timestamp)?.dateValue()
        self.refundedAt = (data["refundedAt"] as? Timestamp)?.dateValue()
    }
}
