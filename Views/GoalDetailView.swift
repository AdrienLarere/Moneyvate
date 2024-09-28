import SwiftUI

struct GoalDetailView: View {
    @ObservedObject var viewModel: GoalViewModel
    @State private var showingCompletionModal = false
    @State private var selectedDate: Date?
    @State private var goal: Goal

    init(viewModel: GoalViewModel, goal: Goal) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._goal = State(initialValue: goal)
    }

    var body: some View {
        List {
            Section(header: Text("Goal Details")) {
                Text("Title: \(goal.title)")
                Text("Frequency: \(goal.frequency.rawValue)")
                Text("Amount per Success: \(CurrencyHelper.format(amount: goal.amountPerSuccess, currencyCode: goal.currency ?? "USD"))")
                Text("Total Amount: \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                Text("Earned Amount: \(CurrencyHelper.format(amount: goal.earnedAmount, currencyCode: goal.currency ?? "USD"))")

            }
            
            Section(header: Text("Progress")) {
                ForEach(getDateRange(), id: \.self) { date in
                    HStack {
                        Text(formatDate(date))
                        Spacer()
                        completionStatusView(for: date)
                    }
                }
            }
        }
        .navigationTitle(goal.title)
        .onAppear {
            viewModel.checkAndUpdateMissedCompletions(for: goal) {
                refreshGoal()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshGoal()
        }
        .sheet(isPresented: $showingCompletionModal) {
            if let date = selectedDate {
                CompletionModalView(viewModel: viewModel, goal: $goal, date: date) {
                    refreshGoal()
                }
            }
        }
        .onChange(of: showingCompletionModal) { oldValue, newValue in
            if !newValue {
                print("CompletionModal dismissed, refreshing goal")
                refreshGoal()
            }
        }
        .onReceive(viewModel.$goals) { goals in
            if let updatedGoal = goals.first(where: { $0.id == goal.id }) {
                self.goal = updatedGoal
            }
        }
    }
    
    private func completionStatusView(for date: Date) -> some View {
        let dateString = DateFormatterHelper.shared.string(from: date) // Use consistent date string
        
        if let completion = goal.completions[dateString] {
            return AnyView(completionStatusText(for: completion))
        } else if canCompleteForDate(date) {
            print("Can complete for date: \(dateString)")
            return AnyView(Button("Complete") {
                selectedDate = date
                showingCompletionModal = true
            }
            .buttonStyle(BorderlessButtonStyle()))
        } else if isPast(date) {
            return AnyView(Text("Missed")
                .italic()
                .foregroundColor(.orange))
        } else {
            return AnyView(Text("Upcoming")
                .font(.caption)
                .foregroundColor(.gray))
        }
    }

    private func completionStatusText(for completion: Completion) -> some View {
        print("Generating status text for completion. Status: \(completion.status)")
        switch completion.status {
        case .pendingVerification:
            return Text("Pending Verification").italic().foregroundColor(.gray)
        case .verified:
            return Text("Verified").italic().foregroundColor(.green)
        case .refunded:
            return Text("Refunded").italic().foregroundColor(.green)
        case .refundFailed:
            return Text("Refund Failed").italic().foregroundColor(.red)
        case .rejected:
            return Text("Rejected").italic().foregroundColor(.red.opacity(0.6))
        case .missed:
            return Text("Missed").italic().foregroundColor(.orange)
        }
    }
    
    private func canCompleteForDate(_ date: Date) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let isToday = Calendar.current.isDate(date, inSameDayAs: today)
        let dateString = DateFormatterHelper.shared.string(from: date)
        let hasNoCompletion = goal.completions[dateString] == nil

        switch goal.frequency {
        case .daily:
            return isToday && hasNoCompletion
        case .weekdays:
            return isToday && !Calendar.current.isDateInWeekend(date) && hasNoCompletion
        case .weekends:
            return isToday && Calendar.current.isDateInWeekend(date) && hasNoCompletion
        case .xDays:
            let completedCount = goal.completions.values.filter { $0.status == .verified || $0.status == .refunded }.count
            return isToday && completedCount < goal.requiredCompletions && hasNoCompletion
        }
    }
    
    private func getDateRange() -> [Date] {
        let calendar = Calendar.current

        let startDate = calendar.startOfDay(for: goal.startDate)
        let endDate = calendar.startOfDay(for: goal.endDate)

        guard let days = calendar.dateComponents([.day], from: startDate, to: endDate).day else {
            return []
        }

        let totalDays = days + 1

        let allDates = (0..<totalDays).compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }

        switch goal.frequency {
        case .daily, .xDays:
            return allDates
        case .weekdays:
            return allDates.filter { !calendar.isDateInWeekend($0) }
        case .weekends:
            return allDates.filter { calendar.isDateInWeekend($0) }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private func isPast(_ date: Date) -> Bool {
        date < Calendar.current.startOfDay(for: Date())
    }
    
    private func refreshGoal() {
        if let goalId = goal.id, let updatedGoal = viewModel.getGoal(withId: goalId) {
            self.goal = updatedGoal
        }
    }
}
