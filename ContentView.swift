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
    
//    private var totalEarnedBackPerCurrency: [String: Double] {
//        var totals = [String: Double]()
//        for goal in viewModel.goals {
//            let currency = goal.currency ?? "USD"
//            totals[currency, default: 0] += goal.earnedAmount
//        }
//        return totals
//    }
    
    private var mainView: some View {
        NavigationView {
            List {
//                ForEach(totalEarnedBackPerCurrency.keys.sorted(), id: \.self) { currency in
//                    Text("Total Earned Back (\(currency.uppercased())): \(CurrencyHelper.format(amount: totalEarnedBackPerCurrency[currency]!, currencyCode: currency))")
//                        .foregroundColor(.primary)
//                }
//                .listRowInsets(EdgeInsets(top: 25, leading: 0, bottom: 0, trailing: 0))
//                .listRowBackground(Color.clear)
                
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
                    .environmentObject(viewModel)     // Pass viewModel
                    .environmentObject(userManager)   // Pass userManager
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
        let today = Calendar.current.startOfDay(for: Date())
        return viewModel.goals
            .filter { goal in
                let goalStartDate = Calendar.current.startOfDay(for: goal.startDate)
                let goalEndDate = Calendar.current.startOfDay(for: goal.endDate)
                let isCurrentGoal = goalStartDate <= today && goalEndDate >= today
                return isCurrentGoal
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
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(goal.title)
                    .font(.headline)
                Text("\(CurrencyHelper.format(amount: goal.earnedAmount, currencyCode: goal.currency ?? "USD")) / \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                if shouldShowNotificationDot {
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
    
    private var shouldShowNotificationDot: Bool {
        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        let isActiveGoal = goal.startDate <= today && goal.endDate >= today

        if !isActiveGoal {
            return false
        }
        
        let todayCompletions = goal.completions.values.filter { Calendar.current.isDate($0.date, inSameDayAs: today) }
        
        let hasValidCompletionToday = todayCompletions.contains { completion in
            completion.status == .verified || completion.status == .refunded || completion.status == .pendingVerification
        }

        let shouldShow: Bool
        switch goal.frequency {
        case .daily:
            shouldShow = !hasValidCompletionToday
        case .xDays:
            let completedCount = goal.completions.values.filter { $0.status == .verified || $0.status == .refunded }.count
            shouldShow = completedCount < goal.requiredCompletions && !hasValidCompletionToday
        case .weekdays:
            let isWeekday = !Calendar.current.isDateInWeekend(today)
            shouldShow = isWeekday && !hasValidCompletionToday
        case .weekends:
            let isWeekend = Calendar.current.isDateInWeekend(today)
            shouldShow = isWeekend && !hasValidCompletionToday
        }
        
        return shouldShow
    }
    
    private var completedCompletionsCount: Int {
        goal.completions.values.filter { $0.status == .verified || $0.status == .refunded }.count
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
