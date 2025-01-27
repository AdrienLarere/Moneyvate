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
            // Same "Goal Details" section
            Section(header: Text("Goal Details")) {
                Text("Title: \(goal.title)")
                Text("Frequency: \(goal.frequency.rawValue)")
                Text("Amount per Success: \(CurrencyHelper.format(amount: goal.amountPerSuccess, currencyCode: goal.currency ?? "USD"))")
                Text("Total Amount: \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                Text("Earned Amount: \(CurrencyHelper.format(amount: viewModel.earnedAmount(for: goal), currencyCode: goal.currency ?? "USD"))")
            }
            
            Section(header: Text("Progress")) {
                // Use the same getDateRange() to list dates
                ForEach(getDateRange(), id: \.self) { date in
                    HStack {
                        Text(formatDate(date))
                        Spacer()
                        // Instead of referencing goal.completions, we look up the completion in the sub-collection data
                        completionStatusView(for: date)
                    }
                }
            }
        }
        .navigationTitle(goal.title)
        .onAppear {
            // 1) Fetch sub-collection completions for this goal
            viewModel.fetchCompletions(for: goal)
            
            // 2) Also run your missed-completions logic if you still want that
            //    (Though eventually you'd adapt this to the sub-collection approach)
            viewModel.markMissedCompletions(for: goal) {
                refreshGoal()
            }
        }
        // If app becomes active, refresh local goal data
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            refreshGoal()
            // You might also want to re-fetch completions
            viewModel.fetchCompletions(for: goal)
        }
        // Show the modal when user taps "Verify"
        .sheet(isPresented: $showingCompletionModal) {
            if let date = selectedDate {
                // Note: This modal still references the old approach if it modifies goal.completions
                // We’ll assume you updated CompletionModalView to call viewModel.updateCompletionStatus(for:on:)
                CompletionModalView(viewModel: viewModel, goal: $goal, date: date) {
                    refreshGoal()
                }
            }
        }
        .onChange(of: showingCompletionModal) { oldValue, newValue in
            if !newValue {
                print("CompletionModal dismissed, refreshing goal")
                refreshGoal()
                // Also re-fetch sub-collection completions
                viewModel.fetchCompletions(for: goal)
            }
        }
        // Listen for changes in the parent goals array. When the specific goal doc is updated,
        // we update our local `goal` so the main fields (title, totalAmount, etc.) remain in sync.
        .onReceive(viewModel.$goals) { goals in
            if let updatedGoal = goals.first(where: { $0.id == goal.id }) {
                self.goal = updatedGoal
            }
        }
    }
    
    // MARK: - Subviews & Helpers
    
    /// Looks up the completion for a specific date in the sub-collection array
    private func completionForDate(_ date: Date) -> Completion? {
        guard let goalId = goal.id else { return nil }
        guard let completions = viewModel.completionsByGoal[goalId] else {
            return nil
        }
        // We compare just the day, ignoring time
        return completions.first {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }
    
    /// A more nuanced approach to handle .nonSubmitted logic
    private func completionStatusView(for date: Date) -> some View {
        // 1) If there's a doc in sub-collection for this date:
        if let completion = completionForDate(date) {
            return AnyView(viewForExistingCompletion(completion, date: date))
        }
        else {
            // 2) If there's *no doc* for this date
            return AnyView(viewForNoCompletionDoc(date))
        }
    }

    /// For a date *with* an existing completion doc
    private func viewForExistingCompletion(_ completion: Completion, date: Date) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        
        switch completion.status {
        case .nonSubmitted:
            if date < today {
                // Past date, not verified => missed
                return AnyView(Text("Missed")
                    .italic()
                    .foregroundColor(.orange))
            } else if date == today {
                // Show "Verify" button
                return AnyView(Button("Verify") {
                    selectedDate = date
                    showingCompletionModal = true
                }
                .buttonStyle(BorderlessButtonStyle()))
            } else {
                // Future date => upcoming
                return AnyView(Text("Upcoming")
                    .font(.caption)
                    .foregroundColor(.gray))
            }
        case .pendingVerification:
            return AnyView(Text("Pending Verification").italic().foregroundColor(.gray))
        case .verified:
            return AnyView(Text("Verified").italic().foregroundColor(.green))
        case .refunded:
            return AnyView(Text("Refunded").italic().foregroundColor(.green))
        case .refundFailed:
            return AnyView(Text("Refund Failed").italic().foregroundColor(.red))
        case .rejected:
            return AnyView(Text("Rejected").italic().foregroundColor(.red.opacity(0.6)))
        case .missed:
            return AnyView(Text("Missed").italic().foregroundColor(.orange))
        }
    }


    /// For a date with *no* completion doc in sub-collection
    private func viewForNoCompletionDoc(_ date: Date) -> some View {
        let today = Calendar.current.startOfDay(for: Date())
        
        if date < today {
            // Past date, not verified => missed
            return AnyView(Text("Missed")
                .italic()
                .foregroundColor(.orange))
        } else if date == today {
            // Show "Verify" button
            return AnyView(Button("Verify") {
                selectedDate = date
                showingCompletionModal = true
            }
            .buttonStyle(BorderlessButtonStyle()))
        } else {
            // Future date => upcoming
            return AnyView(Text("Upcoming")
                .font(.caption)
                .foregroundColor(.gray))
        }
    }

    /// Renders the textual status for an existing Completion doc
    private func completionStatusText(for completion: Completion) -> some View {
        switch completion.status {
        case .nonSubmitted:
            return Text("Non Submitted").italic().foregroundColor(.gray)
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
    
    /// Determines if the "Verify" button should appear for this date
    /// - We check if it's 'today' and that there's no existing completion doc.
    private func canCompleteForDate(_ date: Date) -> Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let isToday = Calendar.current.isDate(date, inSameDayAs: today)
        let completionExists = (completionForDate(date) != nil)
        
        // If the goal is xDays, we also check how many completions are verified/refunded so far
        switch goal.frequency {
        case .daily:
            return isToday && !completionExists
        case .weekdays:
            return isToday &&
                   !Calendar.current.isDateInWeekend(date) &&
                   !completionExists
        case .weekends:
            return isToday &&
                   Calendar.current.isDateInWeekend(date) &&
                   !completionExists
        case .xDays:
            // Count how many completions are 'complete' so far
            let completedCount = (viewModel.completionsByGoal[goal.id ?? ""] ?? [])
                .filter { $0.status == .verified || $0.status == .refunded }
                .count
            return isToday &&
                   (completedCount < goal.requiredCompletions) &&
                   !completionExists
        }
    }
    
    private func getDateRange() -> [Date] {
        // Same as before, listing the "display" dates from startDate to endDate
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
    
    /// Refresh the local `goal` data from the viewModel so we stay in sync.
    /// This updates the goal’s main fields (title, totalAmount, etc.), but not sub-collection completions.
    private func refreshGoal() {
        guard let goalId = goal.id else { return }
        if let updatedGoal = viewModel.getGoal(withId: goalId) {
            self.goal = updatedGoal
        }
    }
}
