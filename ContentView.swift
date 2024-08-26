import SwiftUI
import FirebaseAuth

struct ContentView: View {
    @EnvironmentObject var viewModel: GoalViewModel
    @EnvironmentObject var userManager: UserManager
    @State private var showingAddGoal = false
    @State private var isShowingSignUp = false
    
    var body: some View {
        Group {
            if userManager.isAuthenticated {
                if userManager.isEmailVerified {
                    mainView
                } else {
                    EmailVerificationView()
                }
            } else {
                if userManager.isNewUser {
                    EmailVerificationView()
                } else {
                    signInView
                }
            }
        }
        .onChange(of: userManager.isAuthenticated) { oldValue, newValue in
            if newValue {
                DispatchQueue.main.async {
                    self.viewModel.fetchGoals()
                }
            } else {
                DispatchQueue.main.async {
                    self.viewModel.clearGoals()
                }
            }
        }
    }
    
    private var signInView: some View {
        SignInView(isShowingSignUp: $isShowingSignUp)
            .sheet(isPresented: $isShowingSignUp) {
                SignUpView()
            }
    }
    
    private var mainView: some View {
        NavigationView {
            List {
                Section(header: Text("Current Balance: £\(viewModel.balance, specifier: "%.2f")")) {
                    ForEach(viewModel.goals) { goal in
                        NavigationLink(destination: GoalDetailView(goal: goal)) {
                            GoalRowView(goal: goal)
                        }
                    }
                }
            }
            .navigationTitle("Moneyvate")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddGoal = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Sign Out") {
                        userManager.signOut()
                    }
                }
            }
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView(isPresented: $showingAddGoal)
            }
        }
    }
}

struct GoalRowView: View {
    let goal: Goal
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(goal.title)
                    .font(.headline)
                Text("£\(goal.earnedAmount, specifier: "%.2f") / £\(goal.totalAmount, specifier: "%.2f")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(goal.completions.values.filter { $0 }.count)/\(goal.requiredCompletions)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
