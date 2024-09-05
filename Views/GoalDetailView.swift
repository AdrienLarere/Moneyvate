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
                Text("Amount per Success: £\(goal.amountPerSuccess, specifier: "%.2f")")
                Text("Total Amount: £\(goal.totalAmount, specifier: "%.2f")")
                Text("Earned Amount: £\(goal.earnedAmount, specifier: "%.2f")")
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
        .onAppear(perform: refreshGoal)
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
    }
    
    private func completionStatusView(for date: Date) -> some View {
        let dateString = ISO8601DateFormatter().string(from: date)
        print("Checking completion status for date: \(dateString)")
        
        if let completion = goal.completions[dateString] {
            print("Completion found for date: \(dateString), status: \(completion.status)")
            return AnyView(completionStatusText(for: completion))
        } else if canCompleteForDate(date) {
            print("Can complete for date: \(dateString)")
            return AnyView(Button("Complete") {
                selectedDate = date
                showingCompletionModal = true
            }
            .buttonStyle(BorderlessButtonStyle()))
        } else if isPast(date) {
            print("Date is in the past: \(dateString)")
            return AnyView(Text("Missed")
                .italic()
                .foregroundColor(.orange))
        } else {
            print("Date is upcoming: \(dateString)")
            return AnyView(Text("Upcoming")
                .font(.caption)
                .foregroundColor(.gray))
        }
    }

    private func completionStatusText(for completion: Completion) -> some View {
        switch completion.status {
        case .pendingVerification:
            return Text("Pending").italic().foregroundColor(.gray)
        case .verified:
            return Text("Verified").italic().foregroundColor(.green)
        case .refunded:
            return Text("Refunded").italic().foregroundColor(.green)
        case .rejected:
            return Text("Rejected").italic().foregroundColor(.red.opacity(0.6))
        case .missed:
            return Text("Missed").italic().foregroundColor(.orange)
        }
    }
    
    private func canCompleteForDate(_ date: Date) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let isToday = Calendar.current.isDate(date, inSameDayAs: today)
        let hasNoCompletion = goal.completionDates[date] == nil

        switch goal.frequency {
        case .daily:
            return isToday && hasNoCompletion
        case .weekdays:
            return isToday && !Calendar.current.isDateInWeekend(date) && hasNoCompletion
        case .weekends:
            return isToday && Calendar.current.isDateInWeekend(date) && hasNoCompletion
        case .xDays:
            let completedCount = goal.completions.values.filter { $0.status == .verified }.count
            return isToday && completedCount < goal.requiredCompletions && hasNoCompletion
        }
    }
    
    private func getDateRange() -> [Date] {
        guard let days = Calendar.current.dateComponents([.day], from: goal.startDate, to: goal.endDate).day else {
            return []
        }
        
        let allDates = (0...days).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: goal.startDate) }
        
        switch goal.frequency {
        case .daily, .xDays:
            return allDates
        case .weekdays:
            return allDates.filter { !Calendar.current.isDateInWeekend($0) }
        case .weekends:
            return allDates.filter { Calendar.current.isDateInWeekend($0) }
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
            // Update the goal in the viewModel
            viewModel.updateGoal(updatedGoal)
        }
    }
}
