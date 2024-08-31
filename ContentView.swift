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
                Text("Balance: £\(viewModel.balance, specifier: "%.2f")")
                    .foregroundColor(.primary)
                    .listRowInsets(EdgeInsets(top: 25, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                
                if !currentGoals.isEmpty {
                    Section(header: Text("Current Goals")) {
                        goalList(goals: currentGoals)
                    }
                }
                
                if !futureGoals.isEmpty {
                    Section(header: Text("Future Goals")) {
                        goalList(goals: futureGoals)
                    }
                }
                
                if !pastGoals.isEmpty {
                    Section(header: Text("Past Goals")) {
                        goalList(goals: pastGoals)
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
    
    private func goalList(goals: [Goal]) -> some View {
        ForEach(goals) { goal in
            NavigationLink(destination: GoalDetailView(viewModel: viewModel, goal: Binding.constant(goal))) {
                GoalRowView(goal: goal)
            }
        }
    }
    
    private var currentGoals: [Goal] {
        let now = Date()
        return viewModel.goals
            .filter { $0.startDate <= now && $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
    }
    
    private var futureGoals: [Goal] {
        let now = Date()
        return viewModel.goals
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }
    }
    
    private var pastGoals: [Goal] {
        let now = Date()
        return viewModel.goals
            .filter { $0.endDate < now }
            .sorted { $0.startDate < $1.startDate }
    }
}

struct GoalRowView: View {
    let goal: Goal
    @State private var isPulsating = false
    
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
            VStack(alignment: .trailing) {
                if hasCompletionDueToday {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                }
                Text("\(completedCompletionsCount)/\(goal.requiredCompletions)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var completedCompletionsCount: Int {
        goal.completions.values.filter { $0.status == .verified }.count
    }
    
    private var hasCompletionDueToday: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        return goal.startDate <= today && goal.endDate >= today && !goal.completions.values.contains { completion in
            Calendar.current.isDate(completion.date, inSameDayAs: today) && completion.status == .verified
        }
    }
}
