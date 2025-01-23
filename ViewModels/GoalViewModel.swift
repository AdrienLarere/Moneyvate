import Foundation
import FirebaseFirestore
import FirebaseAuth

class GoalViewModel: ObservableObject {
    @Published var goals: [Goal] = []
    @Published var balance: Double = 0
    @Published var completionsByGoal: [String: [Completion]] = [:]

    private var db = Firestore.firestore()
    private var listenerRegistration: ListenerRegistration?
    
    var totalEarnedBack: Double {
        goals.reduce(0.0) { partial, goal in
            partial + earnedAmount(for: goal)
        }
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
                 currency: String,
                 paymentIntentId: String?) {

        let totalAmount = Double(requiredCompletions) * amountPerSuccess
        guard let userId = Auth.auth().currentUser?.uid else { return }

        let newGoal = Goal(
            id: nil,
            userId: userId,
            title: title,
            frequency: frequency,
            amountPerSuccess: amountPerSuccess,
            startDate: startDate,
            endDate: endDate,
            totalAmount: totalAmount,
            verificationMethod: verificationMethod,
            currency: currency,
            paymentIntentId: paymentIntentId
        )
        
        do {
            // 1) Add the goal doc
            let goalRef = try db.collection("users")
                .document(userId)
                .collection("goals")
                .addDocument(from: newGoal)
            
            // 2) Retrieve the newly created doc's ID
            let docId = goalRef.documentID
            print("Successfully created goal doc with ID: \(docId)")
            
            // 3) Immediately create the sub-collection docs
            createInitialCompletions(
                userId: userId,
                goalId: docId,
                frequency: frequency,
                startDate: startDate,
                endDate: endDate,
                amountPerSuccess: amountPerSuccess,
                requiredCompletions: requiredCompletions,
                verificationMethod: verificationMethod
            )
            
        } catch {
            print("Error adding goal: \(error.localizedDescription)")
        }
    }

    
    func addCompletion(for goal: Goal, on date: Date, verificationPhotoUrl: String? = nil) {
        guard let userId = Auth.auth().currentUser?.uid,
              let goalId = goal.id else { return }

        let completionsRef = db.collection("users")
                               .document(userId)
                               .collection("goals")
                               .document(goalId)
                               .collection("completions")

        // 1) Query the sub-collection for a doc with the matching date
        //    (or we can store the docID as a string of the date, or just query with a whereField).
        // Create the "YYYY-MM-dd" string for the query
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dayString = dateFormatter.string(from: date)
        
        completionsRef
            .whereField("dateString", isEqualTo: dayString)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching completion docs: \(error)")
                    return
                }

                guard let doc = snapshot?.documents.first else {
                    print("No existing completion doc for that date—create one now or fail out.")
                    return
                }

                // 2) Update the status to .verified or .pendingVerification
                let completionDocRef = completionsRef.document(doc.documentID)
                let newStatus: Completion.CompletionStatus = (goal.verificationMethod == .selfVerify) ? .verified : .pendingVerification
                completionDocRef.updateData([
                    "status" : newStatus.rawValue,
                    "verificationPhotoUrl": verificationPhotoUrl ?? NSNull(),
                    "verifiedAt": (newStatus == .verified) ? Timestamp(date: Date()) : NSNull()
                ]) { err in
                    if let err = err {
                        print("Error updating completion doc: \(err)")
                    } else {
                        print("Completion updated for date \(date).")
                    }
                }
            }
    }
    
    func fetchCompletions(for goal: Goal) {
        guard let userId = Auth.auth().currentUser?.uid,
              let goalId = goal.id else { return }
        
        db.collection("users")
          .document(userId)
          .collection("goals")
          .document(goalId)
          .collection("completions")
          .addSnapshotListener { [weak self] snapshot, error in
              if let error = error {
                  print("Error fetching completions: \(error)")
                  return
              }
              guard let documents = snapshot?.documents else { return }
              
              // Convert each Firestore document into a Completion model
              let completions = documents.compactMap { doc -> Completion? in
                  return try? doc.data(as: Completion.self)
              }
              
              // Sort by date if you want them in chronological order
              let sortedCompletions = completions.sorted { $0.date < $1.date }
              
              // Store them in the dictionary
              DispatchQueue.main.async {
                  self?.completionsByGoal[goalId] = sortedCompletions
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
    
    func markMissedCompletions(for goal: Goal, completion: @escaping () -> Void = {}) {
        guard let userId = Auth.auth().currentUser?.uid,
              let goalId = goal.id else {
            completion()
            return
        }
        
        let completionsRef = db.collection("users")
            .document(userId)
            .collection("goals")
            .document(goalId)
            .collection("completions")
        
        let today = Calendar.current.startOfDay(for: Date())
        
        completionsRef.getDocuments { [weak self] (snapshot, error) in
            if let error = error {
                print("Error fetching completions for missed-check: \(error)")
                completion()
                return
            }
            guard let documents = snapshot?.documents else {
                completion()
                return
            }

            var docsToUpdate: [DocumentReference] = []
            
            // Use 'try?' so it returns nil (instead of throwing) if decoding fails
            for doc in documents {
                if let completionObj = try? doc.data(as: Completion.self) {
                    // If date < today and status == .pendingVerification => mark missed
                    if completionObj.date < today,
                       completionObj.status == .pendingVerification {
                        docsToUpdate.append(doc.reference)
                    }
                }
            }
            
            guard let self = self, !docsToUpdate.isEmpty else {
                print("No completions need to be marked missed for goal \(goalId).")
                completion()
                return
            }
            
            // Batch update to set 'status' => 'missed'
            let batch = self.db.batch()
            for ref in docsToUpdate {
                batch.updateData(["status": Completion.CompletionStatus.missed.rawValue], forDocument: ref)
            }
            batch.commit { batchError in
                if let batchError = batchError {
                    print("Error marking missed completions in batch: \(batchError)")
                } else {
                    print("Successfully marked \(docsToUpdate.count) completions as missed for goal \(goalId).")
                }
                completion()
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
                
//                if snapshot.metadata.isFromCache {
//                    print("Data came from cache")
//                } else {
//                    print("Data came from server")
//                }
                
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
    
    private func createInitialCompletions(userId: String,
                                          goalId: String,
                                          frequency: Goal.Frequency,
                                          startDate: Date,
                                          endDate: Date,
                                          amountPerSuccess: Double,
                                          requiredCompletions: Int,
                                          verificationMethod: Goal.VerificationMethod) {

        let completionDates = self.calculateCompletionDates(
            frequency: frequency,
            startDate: startDate,
            endDate: endDate,
            requiredCompletions: requiredCompletions
        )

        let completionsRef = db.collection("users")
                               .document(userId)
                               .collection("goals")
                               .document(goalId)
                               .collection("completions")
        
        let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"

        for date in completionDates {
            let dayString = formatter.string(from: date)
            
            let newCompletion = Completion(
                goalId: goalId,
                date: date,
                dateString: dayString,
                status: date < Calendar.current.startOfDay(for: Date()) ? .missed : .pendingVerification,
                verificationPhotoUrl: nil,
                verifiedAt: nil,
                refundedAt: nil
            )

            do {
                let _ = try completionsRef.addDocument(from: newCompletion)
                print("Added completion doc for \(dayString) in goalId = \(goalId)")
                print(">>> Storing doc with dateString:", dayString)
            } catch {
                print("Error creating completion doc for date \(date): \(error)")
            }
        }
        print("Created \(completionDates.count) completion docs for goalId=\(goalId).")
    }

    
    private func calculateCompletionDates(frequency: Goal.Frequency,
                                          startDate: Date,
                                          endDate: Date,
                                          requiredCompletions: Int) -> [Date] {

        var dates: [Date] = []
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)

        switch frequency {
        case .daily:
            // All days from start to end
            var day = start
            while day <= end {
                dates.append(day)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        case .weekdays:
            var day = start
            while day <= end {
                let weekday = calendar.component(.weekday, from: day)
                // Sunday = 1, Monday = 2, ... Saturday = 7
                if weekday >= 2 && weekday <= 6 { // Monday=2 .. Friday=6
                    dates.append(day)
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        case .weekends:
            var day = start
            while day <= end {
                let weekday = calendar.component(.weekday, from: day)
                // weekend if Sunday=1 or Saturday=7
                if weekday == 1 || weekday == 7 {
                    dates.append(day)
                }
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
        case .xDays:
            // Option 1: If you want to create *all* days, letting user choose any X to complete
            // This is simpler for data structure. We just create them all, but only "X" are needed.
            // The user gets refunds for whichever X days they verify.
            // If you actually want to limit doc creation to exactly X random days, you'd need logic to pick which days.
            // But typically we'd create all days, then only allow X refunds in total.

            var allDays: [Date] = []
            var day = start
            while day <= end {
                allDays.append(day)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            // We'll return allDays. The "X" limit is enforced by your business logic (only X can be refunded).
            // If you *really* want to pre-select exactly X docs, you can do so here, but it's more complex.
            dates = allDays
        }

        return dates
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
        guard let userId = Auth.auth().currentUser?.uid,
              let goalId = goal.id,
              let paymentIntentId = goal.paymentIntentId else {
            completion(.failure(NSError(domain: "GoalViewModel", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid user, goal ID, or payment intent ID"])))
            return
        }
        
        let completionsRef = db.collection("users")
            .document(userId)
            .collection("goals")
            .document(goalId)
            .collection("completions")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dayString = dateFormatter.string(from: date)
        
        // Updated query to use "dateString"
        completionsRef
            .whereField("dateString", isEqualTo: dayString)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let docs = snapshot?.documents, let doc = docs.first else {
                    // No existing doc for that date
                    completion(.failure(NSError(domain: "GoalViewModel", code: 2,
                                                userInfo: [NSLocalizedDescriptionKey: "Completion not found for that date"])))
                    return
                }
        
                // 2) Decode it to check if status == .verified
                do {
                    let completionObj = try doc.data(as: Completion.self)
                    if completionObj.status != .verified {
                        completion(.failure(NSError(domain: "GoalViewModel", code: 2,
                                                    userInfo: [NSLocalizedDescriptionKey: "Completion not verified"])))
                        return
                    }
                } catch {
                    completion(.failure(error))
                    return
                }
        
                // 3) Proceed to refund
                self?.processRefund(paymentIntentId: paymentIntentId,
                                    amount: Int(goal.amountPerSuccess * 100)) { result in
                    switch result {
                    case .success:
                        // 4) Mark that completion doc as 'refunded' in Firestore
                        let docRef = completionsRef.document(doc.documentID)
                        docRef.updateData([
                            "status": Completion.CompletionStatus.refunded.rawValue,
                            "refundedAt": Timestamp(date: Date())
                        ]) { error in
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                // 5) Refresh local sub-collection data
                                self?.fetchCompletions(for: goal)
                                
                                // (Optional) Recalculate balance if your balance depends on refunds
                                self?.updateBalance()
                                self?.objectWillChange.send()
                                
                                completion(.success(()))
                            }
                        }
                        
                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
    }

    
    func earnedAmount(for goal: Goal) -> Double {
        guard let goalId = goal.id,
              let completions = completionsByGoal[goalId] else {
            return 0.0
        }
        let refundedCount = completions.filter { $0.status == .refunded }.count
        return Double(refundedCount) * goal.amountPerSuccess
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
        balance = goals.reduce(0.0) { partial, goal in
            let earned = earnedAmount(for: goal)
            return partial + (earned - goal.totalAmount)
        }
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
