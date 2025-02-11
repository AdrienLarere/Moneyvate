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
    
    func addGoal(
        title: String,
        frequency: Goal.Frequency,
        amountPerSuccess: Double,
        startDate: Date,
        endDate: Date,
        requiredCompletions: Int,
        verificationMethod: Goal.VerificationMethod,
        currency: String,
        paymentIntentId: String? = nil,
        selectedXDays: Int? = nil
    ) -> Goal? {
        // 1) Ensure we have an authenticated user
        guard let userId = Auth.auth().currentUser?.uid else {
            print("No authenticated user.")
            return nil
        }
        
        let totalAmount = Double(requiredCompletions) * amountPerSuccess
        
        // 2) Generate a new Firestore doc reference so we have the docID
        let goalRef = db.collection("users")
                        .document(userId)
                        .collection("goals")
                        .document()
        
        // 3) Build a Goal with that docID
        let docId = goalRef.documentID
        let newGoal = Goal(
            id: docId,
            userId: userId,
            title: title,
            frequency: frequency,
            amountPerSuccess: amountPerSuccess,
            startDate: startDate,
            endDate: endDate,
            totalAmount: totalAmount,
            verificationMethod: verificationMethod,
            currency: currency,
            paymentIntentId: paymentIntentId,
            selectedXDays: selectedXDays
        )
        
        // 4) Write the Goal to Firestore
        do {
            // This sets the entire document data from `newGoal`
            try goalRef.setData(from: newGoal)
            print("Successfully created goal doc with ID: \(docId)")
            
            // 5) Optionally create initial completions right away
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
            
            // 6) Return the new Goal (with an actual ID!)
            return newGoal
            
        } catch {
            print("Error adding goal: \(error.localizedDescription)")
            return nil
        }
    }

    
    func verifyCompletion(
        for goal: Goal,
        dayString: String,
        verificationPhotoUrl: String? = nil,
        explanation: String? = nil
    ) {
        guard let userId = Auth.auth().currentUser?.uid,
              let goalId = goal.id else { return }

        let completionsRef = db.collection("users")
            .document(userId)
            .collection("goals")
            .document(goalId)
            .collection("completions")

        print(">>> verifyCompletion() dayString=\(dayString)")

        completionsRef
            .whereField("dateString", isEqualTo: dayString)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error fetching completion docs for dayString=\(dayString): \(error)")
                    return
                }
                guard let doc = snapshot?.documents.first else {
                    print("❌ No existing completion doc for dayString=\(dayString).")
                    return
                }
                print("✅ Found doc with ID=\(doc.documentID). Updating status...")

                // If 'photoVerification', set .pendingVerification;
                // If 'selfVerify', set .verified
                let newStatus: Completion.CompletionStatus = {
                    if goal.verificationMethod == .selfVerify {
                        return .verified
                    } else {
                        return .pendingVerification
                    }
                }()

                // Build the update dictionary
                var updateData: [String: Any] = [
                    "status" : newStatus.rawValue,
                    "verificationPhotoUrl": verificationPhotoUrl ?? NSNull(),
                    // Only set verifiedAt if newStatus == .verified
                    "verifiedAt": (newStatus == .verified) ? Timestamp(date: Date()) : NSNull()
                ]

                // If the user typed an explanation
                if let explanation = explanation, !explanation.isEmpty {
                    updateData["explanation"] = explanation
                }

                doc.reference.updateData(updateData) { err in
                    if let err = err {
                        print("Error updating completion doc: \(err)")
                    } else {
                        print("Completion doc updated to \(newStatus) for dayString=\(dayString).")
                        // Optionally call self?.fetchCompletions(for: goal) to refresh
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
        
        // "todayLocal" is the local midnight for the current user’s time zone
        let todayLocal = Calendar.current.startOfDay(for: Date())
        
        completionsRef.getDocuments { [weak self] snapshot, error in
            // Early unwrapping of self
            guard let self = self else {
                completion()
                return
            }
            
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
            
            for doc in documents {
                if let completionObj = try? doc.data(as: Completion.self) {
                    // 1) We only mark "nonSubmitted" as missed if it's before "today"
                    guard completionObj.status == .nonSubmitted else { continue }
                    
                    // 2) Parse the doc’s dateString into local midnight using self
                    if let docLocalDate = self.parseLocalMidnight(completionObj.dateString ?? "") {
                        // 3) Compare docLocalDate < todayLocal
                        if docLocalDate < todayLocal {
                            docsToUpdate.append(doc.reference)
                        }
                    } else {
                        print("Unable to parse dateString for doc: \(doc.documentID)")
                    }
                }
            }
            
            guard !docsToUpdate.isEmpty else {
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

    
    private func parseLocalMidnight(_ dayString: String) -> Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        return df.date(from: dayString)
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
                    
                    // **Fetch completions** for each goal (needed for notificationDot)
                    for g in newGoals {
                        self?.fetchCompletions(for: g)
                    }
                    
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
        
        // DateFormatter for local day string
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current  // or omit since .current is default

        for rawDate in completionDates {
            // 1) Force each iteration to local midnight
            let localMidnight = Calendar.current.startOfDay(for: rawDate)
            
            // 2) Convert that local midnight to a day string
            let dayString = formatter.string(from: localMidnight)
            
            // 3) Decide if it's missed vs. pending
            let todayLocalMidnight = Calendar.current.startOfDay(for: Date())
            let status: Completion.CompletionStatus = (localMidnight < todayLocalMidnight)
                ? .missed
                : .nonSubmitted
            
            // 4) Create the doc with localMidnight + dayString
            let newCompletion = Completion(
                goalId: goalId,
                date: localMidnight,
                dateString: dayString,
                status: status,
                verificationPhotoUrl: nil,
                verifiedAt: nil,
                refundedAt: nil
            )
            
            do {
                try completionsRef.addDocument(from: newCompletion)
                print("Created local dateString=\(dayString), localMidnight=\(localMidnight) in goalId=\(goalId)")
            } catch {
                print("Error creating completion doc for date=\(localMidnight): \(error)")
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
    
    func triggerRefund(for goal: Goal, dayString: String, ownerId: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
        // Use ownerId if passed in; otherwise, use current user's UID.
        let actualOwnerId: String
        if let ownerId = ownerId {
            actualOwnerId = ownerId
        } else if let uid = Auth.auth().currentUser?.uid {
            actualOwnerId = uid
        } else {
            completion(.failure(NSError(domain: "GoalViewModel", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid owner ID"])))
            return
        }
        
        guard let goalId = goal.id, let paymentIntentId = goal.paymentIntentId else {
            completion(.failure(NSError(domain: "GoalViewModel", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid goal ID or payment intent"])))
            return
        }
        
        let completionsRef = db.collection("users")
            .document(actualOwnerId)
            .collection("goals")
            .document(goalId)
            .collection("completions")
        
        completionsRef
            .whereField("dateString", isEqualTo: dayString)
            .getDocuments { [weak self] snapshot, error in
                if let error = error {
                    print("triggerRefund: Error fetching completions: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                guard let docs = snapshot?.documents, let doc = docs.first else {
                    print("triggerRefund: No completion found for dayString \(dayString)")
                    completion(.failure(NSError(domain: "GoalViewModel", code: 2,
                                                userInfo: [NSLocalizedDescriptionKey: "Completion not found for that date"])))
                    return
                }
                
                do {
                    let completionObj = try doc.data(as: Completion.self)
                    print("triggerRefund: Fetched completion: \(completionObj)")
                    if completionObj.status != .verified {
                        print("triggerRefund: Completion status is \(completionObj.status.rawValue), not verified.")
                        completion(.failure(NSError(domain: "GoalViewModel", code: 2,
                                                    userInfo: [NSLocalizedDescriptionKey: "Completion not verified"])))
                        return
                    }
                } catch {
                    print("triggerRefund: Error decoding completion: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                self?.processRefund(paymentIntentId: paymentIntentId,
                                    amount: Int(goal.amountPerSuccess * 100)) { result in
                    switch result {
                    case .success:
                        let docRef = completionsRef.document(doc.documentID)
                        docRef.updateData([
                            "status": Completion.CompletionStatus.refunded.rawValue,
                            "refundedAt": Timestamp(date: Date())
                        ]) { error in
                            if let error = error {
                                completion(.failure(error))
                            } else {
                                self?.fetchCompletions(for: goal)
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
    
    
    func triggerFullRefund(for goal: Goal, completion: @escaping (Result<Void, Error>) -> Void) {
        // Calculate the remaining amount to refund.
        let earned = earnedAmount(for: goal)
        let remainingAmountFloat = goal.totalAmount - earned
        // Assuming your Stripe server expects the amount in cents:
        let remainingAmountCents = Int(remainingAmountFloat * 100)
        
        guard let paymentIntentId = goal.paymentIntentId else {
            completion(.failure(NSError(domain: "GoalViewModel", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Missing paymentIntentId"])))
            return
        }
        
        print("Triggering full refund for goal \(goal.title): remaining \(remainingAmountCents) cents")
        
        // Call your existing refund helper. (Ensure processRefund exists.)
        processRefund(paymentIntentId: paymentIntentId, amount: remainingAmountCents) { result in
            completion(result)
        }
    }
    
    
    func triggerLateDeletionRefund(for goal: Goal, completion: @escaping (Result<Void, Error>) -> Void) {
        let earned = earnedAmount(for: goal)
        let remaining = goal.totalAmount - earned
        let tenPercent = goal.totalAmount * 0.10
        
        // If remaining is less than 10% then refund 0.
        let refundAmount = remaining > tenPercent ? remaining - tenPercent : 0.0
        let refundAmountCents = Int(refundAmount * 100)
        
        guard let paymentIntentId = goal.paymentIntentId else {
            completion(.failure(NSError(domain: "GoalViewModel", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Missing paymentIntentId"])))
            return
        }
        
        print("Triggering late deletion refund for goal \(goal.title): refund \(refundAmountCents) cents")
        
        processRefund(paymentIntentId: paymentIntentId, amount: refundAmountCents) { result in
            completion(result)
        }
    }
    
    
    func markGoalAsManuallyRefunded(_ goal: Goal, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = goal.userId, let goalId = goal.id else {
            completion(.failure(NSError(domain: "GoalViewModel", code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: "Missing userId or goalId"])))
            return
        }
        
        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
        goalRef.updateData(["manuallyRefunded": true]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }
    
    
    func markGoalAsDeleted(_ goal: Goal, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let userId = goal.userId, let goalId = goal.id else {
            completion(.failure(NSError(domain: "GoalViewModel", code: 2,
                                        userInfo: [NSLocalizedDescriptionKey: "Missing userId or goalId"])))
            return
        }
        
        let goalRef = db.collection("users").document(userId).collection("goals").document(goalId)
        let now = Date()
        goalRef.updateData([
            "isDeleted": true,
            "deletionDate": Timestamp(date: now)
        ]) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    
    func earnedAmount(for goal: Goal) -> Double {
        guard let goalId = goal.id,
              let completions = completionsByGoal[goalId] else {
            return 0.0
        }
        let successfulCompletions = completions.filter {
            $0.status == .refunded || $0.status == .verified
        }
        return Double(successfulCompletions.count) * goal.amountPerSuccess
    }


    private func processRefund(paymentIntentId: String, amount: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        // Build the refund endpoint URL.
        guard let url = URL(string: "\(AppConfig.serverURL)/refund-payment") else {
            print("DEBUG: Invalid server URL")
            completion(.failure(NSError(domain: "GoalViewModel", code: 3,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])))
            return
        }
        
        print("DEBUG: Initiating refund process for paymentIntentId: \(paymentIntentId), amount: \(amount)")
        
        // Get the ID token for the current user.
        Auth.auth().currentUser?.getIDToken { token, error in
            if let error = error {
                print("DEBUG: Error getting ID token: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let token = token else {
                print("DEBUG: Failed to get authentication token")
                completion(.failure(NSError(domain: "GoalViewModel", code: 6,
                                            userInfo: [NSLocalizedDescriptionKey: "Failed to get authentication token"])))
                return
            }
            
            print("DEBUG: Got token: \(token.prefix(10))... (truncated)")
            
            // Create the URLRequest.
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
                print("DEBUG: Request body: \(body)")
            } catch {
                print("DEBUG: Error creating request body: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            // Create the URLSession data task.
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("DEBUG: Network error: \(error.localizedDescription)")
                    completion(.failure(error))
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("DEBUG: HTTP response status code: \(httpResponse.statusCode)")
                }
                
                guard let data = data else {
                    print("DEBUG: No data received from server")
                    completion(.failure(NSError(domain: "GoalViewModel", code: 4,
                                                userInfo: [NSLocalizedDescriptionKey: "No data received from server"])))
                    return
                }
                
                if let rawResponse = String(data: data, encoding: .utf8) {
                    print("DEBUG: Raw server response: \(rawResponse)")
                } else {
                    print("DEBUG: Unable to convert response data to string")
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("DEBUG: Parsed server response: \(json)")
                        if let success = json["success"] as? Bool, success {
                            print("DEBUG: Refund successful")
                            completion(.success(()))
                        } else {
                            print("DEBUG: Refund failed according to server")
                            completion(.failure(NSError(domain: "GoalViewModel", code: 5,
                                                        userInfo: [NSLocalizedDescriptionKey: "Refund failed"])))
                        }
                    } else {
                        print("DEBUG: Invalid JSON response")
                        completion(.failure(NSError(domain: "GoalViewModel", code: 7,
                                                    userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])))
                    }
                } catch {
                    print("DEBUG: Error parsing server response: \(error.localizedDescription)")
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
