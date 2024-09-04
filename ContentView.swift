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
            NavigationLink(destination: GoalDetailView(viewModel: viewModel, goal: goal)) {
                GoalRowView(goal: goal)
            }
        }
    }
    
    private var currentGoals: [Goal] {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let currentGoals = viewModel.goals
            .filter { goal in
                let isCurrentGoal = goal.startDate <= now && goal.endDate >= today
                return isCurrentGoal
            }
            .sorted { $0.startDate < $1.startDate }
        return currentGoals
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
    @State private var gradientStart = UnitPoint(x: 0, y: 0)
    @State private var gradientEnd = UnitPoint(x: 1, y: 1)
    
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
                if shouldShowNotificationDot {
                    Circle()
                        .fill(
                            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.7), Color.blue]), startPoint: gradientStart, endPoint: gradientEnd)
                        )
                        .frame(width: 10, height: 10)
                        .onAppear {
                            withAnimation(Animation.linear(duration: 2).repeatForever(autoreverses: false)) {
                                self.gradientStart = UnitPoint(x: 1, y: 1)
                                self.gradientEnd = UnitPoint(x: 0, y: 0)
                            }
                        }
                }
                Text("\(completedCompletionsCount)/\(goal.requiredCompletions)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var shouldShowNotificationDot: Bool {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let isActiveGoal = goal.startDate <= now && goal.endDate >= today

        if !isActiveGoal {
            return false
        }
        let hasCompletionToday = goal.hasCompletionForToday()
        let shouldShow: Bool
        switch goal.frequency {
        case .daily:
            shouldShow = !hasCompletionToday
        case .xDays:
            let completedCount = goal.completions.values.filter { $0.status == .verified }.count
            shouldShow = completedCount < goal.requiredCompletions && !hasCompletionToday
        case .weekdays:
            let isWeekday = !Calendar.current.isDateInWeekend(today)
            shouldShow = isWeekday && !hasCompletionToday
        case .weekends:
            let isWeekend = Calendar.current.isDateInWeekend(today)
            shouldShow = isWeekend && !hasCompletionToday
        }
        return shouldShow
    }
    
    private var completedCompletionsCount: Int {
        goal.completions.values.filter { $0.status == .verified }.count
    }
}

extension Calendar {
    func isDateInWeekday(_ date: Date) -> Bool {
        !isDateInWeekend(date)
    }

    func isDateInWeekend(_ date: Date) -> Bool {
        let weekday = self.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }
}
