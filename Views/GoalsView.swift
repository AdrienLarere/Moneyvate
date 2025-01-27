import SwiftUI

struct GoalsView: View {
    @EnvironmentObject var viewModel: GoalViewModel
    @EnvironmentObject var userManager: UserManager
    @State private var showingAddGoal = false
    
    var body: some View {
        NavigationView {
            List {
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Sign Out") {
                        userManager.signOut()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddGoal = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    NavigationLink(destination: AboutView()) {
                        Text("About/Contact")
                            .foregroundColor(.blue)
                            .font(.footnote)
                    }
                    Spacer()
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.blue)
                            .font(.footnote)
                    }
                }
            }
            .sheet(isPresented: $showingAddGoal) {
                AddGoalView(isPresented: $showingAddGoal)
                    .environmentObject(viewModel)
                    .environmentObject(userManager)
            }
        }
    }
    
    private func goalList(goals: [Goal]) -> some View {
        ForEach(goals) { goal in
            NavigationLink(destination: GoalDetailView(viewModel: viewModel, goal: goal)) {
                GoalRowView(goal: goal, viewModel: viewModel)
            }
        }
    }

    private var currentGoals: [Goal] {
        // same logic you had in contentView
        let today = Calendar.current.startOfDay(for: Date())
        return viewModel.goals
            .filter { goal in
                let goalStartDate = Calendar.current.startOfDay(for: goal.startDate)
                let goalEndDate = Calendar.current.startOfDay(for: goal.endDate)
                return goalStartDate <= today && goalEndDate >= today
            }
            .sorted { $0.startDate < $1.startDate }
    }
    
    private var futureGoals: [Goal] {
        let today = Calendar.current.startOfDay(for: Date())
        return viewModel.goals
            .filter {
                let goalStartDate = Calendar.current.startOfDay(for: $0.startDate)
                return goalStartDate > today
            }
            .sorted { $0.startDate < $1.startDate }
    }
    
    private var pastGoals: [Goal] {
        let today = Calendar.current.startOfDay(for: Date())
        return viewModel.goals
            .filter {
                let goalEndDate = Calendar.current.startOfDay(for: $0.endDate)
                return goalEndDate < today
            }
            .sorted { $0.startDate < $1.startDate }
    }
}

struct GoalRowView: View {
    let goal: Goal
    @ObservedObject var viewModel: GoalViewModel
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(goal.title)
                    .font(.headline)
                
                // Show how much earned vs total
                Text("\(CurrencyHelper.format(amount: viewModel.earnedAmount(for: goal), currencyCode: goal.currency ?? "USD")) / \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                // The blue dot logic
                if shouldShowNotificationDot {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 10, height: 10)
                }
                
                // Completed/required ratio
                Text("\(completedCompletionsCount)/\(goal.requiredCompletions)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    /// Number of completions (verified or refunded) so far
    private var completedCompletionsCount: Int {
        guard let goalId = goal.id,
              let completions = viewModel.completionsByGoal[goalId] else {
            return 0
        }
        return completions.filter {
            $0.status == .verified || $0.status == .refunded
        }.count
    }

    /// Decides if we show the blue dot for "pending" logic
    private var shouldShowNotificationDot: Bool {
        // 1) Quick check if goal is active today
        let today = Calendar.current.startOfDay(for: Date())
        let startDay = Calendar.current.startOfDay(for: goal.startDate)
        let endDay = Calendar.current.startOfDay(for: goal.endDate)
        let isActiveGoal = (startDay <= today && endDay >= today)
        guard isActiveGoal else {
            return false
        }
        
        // 2) Retrieve completions for this goal
        guard let goalId = goal.id,
              let completions = viewModel.completionsByGoal[goalId] else {
            return false
        }
        
        // 3) Filter completions that match "today"
        let todayCompletions = completions.filter {
            Calendar.current.isDate($0.date, inSameDayAs: today)
        }
        
        // 4) Option B: Show the dot **only** if there's at least one `.nonSubmitted` doc
        let hasNonSubmittedDocToday = todayCompletions.contains { $0.status == .nonSubmitted }
        
        switch goal.frequency {
        case .daily:
            // Show dot if there's a `.nonSubmitted` doc for today
            return hasNonSubmittedDocToday
            
        case .xDays:
            // Typically, you'd do the same check:
            return hasNonSubmittedDocToday
            
        case .weekdays:
            // Also check if today is a weekday
            let isWeekday = !Calendar.current.isDateInWeekend(today)
            return isWeekday && hasNonSubmittedDocToday
            
        case .weekends:
            // Also check if today is a weekend
            let isWeekend = Calendar.current.isDateInWeekend(today)
            return isWeekend && hasNonSubmittedDocToday
        }
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
