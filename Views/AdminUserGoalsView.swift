import SwiftUI
import FirebaseFirestore

struct AdminUserGoalsView: View {
    let user: UserProfile
    @State private var nonRefundedGoals: [Goal] = []
    @State private var refundedGoals: [Goal] = []
    
    var body: some View {
        List {
            if !nonRefundedGoals.isEmpty {
                Section(header: Text("Nonrefunded Goals")) {
                    ForEach(nonRefundedGoals) { goal in
                        NavigationLink(destination: AdminUserGoalFullRefundView(goal: goal)) {
                            VStack(alignment: .leading) {
                                Text(goal.title)
                                    .font(.headline)
                                Text("Total: \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            
            if !refundedGoals.isEmpty {
                Section(header: Text("Refunded Goals")) {
                    ForEach(refundedGoals) { goal in
                        NavigationLink(destination: AdminUserGoalFullRefundView(goal: goal)) {
                            VStack(alignment: .leading) {
                                Text(goal.title)
                                    .font(.headline)
                                Text("Total: \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Goals")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Custom back button for this view: shows "Users"
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismissView() }) {
                    HStack {
                        Image(systemName: "chevron.left")
                        Text("Users")
                    }
                }
            }
        }
        .onAppear {
            fetchUserGoals()
        }
    }
    
    // Use the presentation mode to dismiss this view.
    @Environment(\.presentationMode) var presentationMode
    private func dismissView() {
        presentationMode.wrappedValue.dismiss()
    }
    
    private func fetchUserGoals() {
        let db = Firestore.firestore()
        db.collection("users").document(user.id ?? "").collection("goals")
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching goals for user: \(error.localizedDescription)")
                } else {
                    let allGoals = snapshot?.documents.compactMap { try? $0.data(as: Goal.self) } ?? []
                    // Split into non-refunded and refunded arrays.
                    nonRefundedGoals = allGoals.filter { ($0.manuallyRefunded ?? false) == false }
                    refundedGoals = allGoals.filter { $0.manuallyRefunded ?? false }
                }
            }
    }
}
