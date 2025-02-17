import SwiftUI

struct GoalsView: View {
    @EnvironmentObject var viewModel: GoalViewModel
    @EnvironmentObject var userManager: UserManager
    
    @State private var showingAddGoal = false
    @State private var showDeletedGoals: Bool = false
    @State private var showPastGoals: Bool = false
    
    private var totalActiveGoals: Int {
        currentGoals.count + futureGoals.count
    }

    private var canAddGoal: Bool {
        // If user is admin, no limit
        if userManager.userProfile?.isAdmin == true {
            return true
        }
        // Otherwise limit is 5
        return totalActiveGoals < 5
    }
    
    var body: some View {
        NavigationView {
            
            VStack(spacing: 0) {
                if !(userManager.userProfile?.isAdmin ?? false) {
                    let maxGoals = 5
                    let progress = Double(totalActiveGoals) / Double(maxGoals)

                    VStack(spacing: 8) {
                        Text("Present + Future Goals: \(totalActiveGoals)/\(maxGoals)")
                            .font(.footnote)

                        // This is the bar from 0..5
                        ProgressView(value: progress)
                            .progressViewStyle(LinearProgressViewStyle())
                            .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 8)
                    .background(Color(UIColor.systemGroupedBackground))
                }
                
                if viewModel.goals.isEmpty {
                    VStack {
                        Spacer()
                        Text("Create your first goal by clicking on the \"+\" sign in the top right corner")
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)  // Increased horizontal padding
                        Spacer()
                    }
                } else {
                    List {
                        if !currentGoals.isEmpty {
                            Section(header: Text("Current Goals")) {
                                goalList(goals: currentGoals)
                            }
                        }
                        if !futureGoals.isEmpty {
                            Section(header: Text("Upcoming Goals")) {
                                goalList(goals: futureGoals)
                            }
                        }
                        if !pastAndCompletedGoals.isEmpty {
                            Section() {
                                DisclosureGroup("Past & Completed Goals", isExpanded: $showPastGoals) {
                                    goalList(goals: pastAndCompletedGoals)
                                }
                            }
                        }
                        if !deletedGoals.isEmpty {
                            Section() {
                                DisclosureGroup("Deleted Goals", isExpanded: $showDeletedGoals) {
                                    goalList(goals: deletedGoals, showMoneyDetails: false)
                                }
                            }
                        }
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
                    // Disable the "+" if canAddGoal == false
                    Button {
                        showingAddGoal = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!canAddGoal)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    NavigationLink(destination: AboutView()) {
                        Text("About/Contact")
                            .foregroundColor(.blue)
                            .font(.footnote)
                    }
                    Spacer()
                    NavigationLink(destination: SettingsView()
                        .environmentObject(viewModel) // pass the same instance used in GoalsView
                    ) {
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
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func goalList(goals: [Goal], showMoneyDetails: Bool = true) -> some View {
        ForEach(goals) { goal in
            NavigationLink(destination: GoalDetailView(viewModel: viewModel, goal: goal)) {
                GoalRowView(goal: goal, viewModel: viewModel, showMoneyDetails: showMoneyDetails)
            }
        }
    }

    private var currentGoals: [Goal] {
        let todayString = Date().toStringLocal(format: "yyyy-MM-dd")
        return viewModel.goals.filter { goal in
            // Exclude deleted and manually refunded goals:
            if goal.isDeleted ?? false { return false }
            if goal.manuallyRefunded ?? false { return false }
            let isActiveToday = (goal.startDateLocalString <= todayString && goal.endDateLocalString >= todayString)
            let completedCount = (viewModel.completionsByGoal[goal.id ?? ""]?
                .filter { $0.status == .verified || $0.status == .refunded }
                .count) ?? 0
            let isCompleted = completedCount >= goal.requiredCompletions
            return isActiveToday && !isCompleted
        }
        .sorted { $0.startDate < $1.startDate }
    }


    
    private var futureGoals: [Goal] {
        let today = Calendar.current.startOfDay(for: Date())
        return viewModel.goals.filter {
            // Exclude deleted and manually refunded goals:
            if $0.isDeleted ?? false { return false }
            if $0.manuallyRefunded ?? false { return false }
            let goalStartDate = Calendar.current.startOfDay(for: $0.startDate)
            return goalStartDate > today
        }
        .sorted { $0.startDate < $1.startDate }
    }


    private var pastAndCompletedGoals: [Goal] {
        let todayString = Date().toStringLocal(format: "yyyy-MM-dd")
        return viewModel.goals.filter { goal in
            let completedCount = (viewModel.completionsByGoal[goal.id ?? ""]?
                .filter { $0.status == .verified || $0.status == .refunded }
                .count) ?? 0
            let isCompleted = completedCount >= goal.requiredCompletions
            // Include if manually refunded OR end date is before today OR goal is completed.
            return (goal.manuallyRefunded ?? false) || goal.endDateLocalString < todayString || isCompleted
        }
        .sorted { $0.startDate < $1.startDate }
    }
    
    
    private var deletedGoals: [Goal] {
        return viewModel.goals.filter { $0.isDeleted ?? false }
            .sorted { $0.startDate < $1.startDate }
    }
    
}

struct GoalRowView: View {
    let goal: Goal
    @ObservedObject var viewModel: GoalViewModel
    var showMoneyDetails: Bool = true
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(goal.title)
                    .font(.headline)
                
                if showMoneyDetails {
                    if goal.manuallyRefunded ?? false {
                        Text("\(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD")) / \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(CurrencyHelper.format(amount: viewModel.earnedAmount(for: goal), currencyCode: goal.currency ?? "USD")) / \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                if shouldShowNotificationDot {
                    PulsatingCircle()
                }
                
                // Show completions ratio.
                // If the goal is manually refunded, show "total completions / total completions"
                if goal.manuallyRefunded ?? false {
                    Text("\(goal.requiredCompletions)/\(goal.requiredCompletions)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(completedCompletionsCount)/\(goal.requiredCompletions)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
        // 0) No notification dot if manually refunded OR deleted
        if goal.manuallyRefunded ?? false { return false }
        if goal.isDeleted ?? false { return false }
    
        // 1) Get today's LOCAL dateString
        let todayDateString = Date().toStringLocal(format: "yyyy-MM-dd")
        
        // 2) Check if goal is active today using LOCAL dates
        let isActiveGoal = goal.startDateLocalString <= todayDateString
                        && goal.endDateLocalString >= todayDateString
        guard isActiveGoal else {
            return false
        }
        
        // 3) Retrieve completions
        guard let goalId = goal.id,
              let completions = viewModel.completionsByGoal[goalId] else {
            return false
        }
        
        // 4) Filter completions with TODAY'S LOCAL dateString
        let todayCompletions = completions.filter {
            $0.dateString == todayDateString
        }
        
        // 5) Check for successful completions first
        let hasSuccessfulCompletion = todayCompletions.contains {
            $0.status == .verified || $0.status == .refunded || $0.status == .pendingVerification
        }
        
        // 6) Check for non-submitted docs
        let hasNonSubmittedDocToday = todayCompletions.contains {
            $0.status == .nonSubmitted
        }
        
        // 7) Check if we've already met required completions
        let completedCount = completedCompletionsCount
        let hasMetRequiredCompletions = completedCount >= goal.requiredCompletions
        
        // 8) Frequency check
        let calendar = Calendar.current
        let localToday = Date() // Already in local time
        let isFrequencyMatch: Bool = {
            switch goal.frequency {
            case .daily:
                return true
            case .xDays:
                // Only show if:
                // - Has non-submitted doc today
                // - Hasn't met required completions
                return !hasMetRequiredCompletions && hasNonSubmittedDocToday
            case .weekdays:
                return !calendar.isDateInWeekend(localToday)
            case .weekends:
                return calendar.isDateInWeekend(localToday)
            }
        }()
        
        return isFrequencyMatch && !hasSuccessfulCompletion
    }
}

struct PulsatingCircle: View {
    @State private var isAnimating = false
    
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 10, height: 10)
            .scaleEffect(isAnimating ? 1.1 : 1.2)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                Animation.easeInOut(duration: 1)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                self.isAnimating = true
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

extension Date {
    func toStringLocal(format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = TimeZone.current // Local timezone
        return formatter.string(from: self)
    }
}
