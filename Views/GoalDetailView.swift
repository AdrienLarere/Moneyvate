import SwiftUI

struct GoalDetailView: View {
    @ObservedObject var viewModel: GoalViewModel
    @State private var showingCompletionModal = false
    @State private var selectedDayString: String?
    @State private var goal: Goal

    init(viewModel: GoalViewModel, goal: Goal) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._goal = State(initialValue: goal)
    }

    var body: some View {
        List {
            // Same "Goal Details" section
            Section(header: Text("Goal Details")) {
                Text("Frequency: \(goal.frequency.rawValue)")
                if goal.frequency == .xDays, let xDays = goal.selectedXDays {
                    Text("Required Completions: \(xDays)")
                }
                Text("Verification Method: \(goal.verificationMethod.rawValue)")
                Text("Amount per Success: \(CurrencyHelper.format(amount: goal.amountPerSuccess, currencyCode: goal.currency ?? "USD"))")
                Text("Total Amount: \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                Text("Earned Amount: \(CurrencyHelper.format(amount: viewModel.earnedAmount(for: goal), currencyCode: goal.currency ?? "USD"))")
            }
            
            Section(header: Text("Progress")) {
                // Use the same getDateRange() to list dates
                ForEach(getDayStringsRange(), id: \.self) { dayStr in
                    HStack {
                        Text(formatDayStringNicely(dayStr))
                        Spacer()
                        // Instead of referencing goal.completions, we look up the completion in the sub-collection data
                        completionStatusView(for: dayStr)
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
            if let dayStr = selectedDayString {
                CompletionModalView(
                    viewModel: viewModel,
                    goal: $goal,
                    dayString: dayStr
                ) {
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
    
    private func formatDayStringNicely(_ dayStr: String) -> String {
        // E.g. parse "2025-01-27" -> "Jan 27, 2025"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        if let date = df.date(from: dayStr) {
            let displayDF = DateFormatter()
            displayDF.dateFormat = "MMM d, yyyy"
            return displayDF.string(from: date)
        }
        return dayStr
    }
    
    /// Looks up the completion for a specific date in the sub-collection array
    private func completionForDayString(_ dayString: String) -> Completion? {
        guard let goalId = goal.id else { return nil }
        guard let completions = viewModel.completionsByGoal[goalId] else {
            return nil
        }
        return completions.first { $0.dateString == dayString }
    }

    
    /// A more nuanced approach to handle .nonSubmitted logic
    private func completionStatusView(for dayString: String) -> some View {
        // Check if we have a doc for that dayString
        if let completion = completionForDayString(dayString) {
            return AnyView(viewForExistingCompletion(completion, dayString: dayString))
        } else {
            return AnyView(viewForNoCompletionDoc(dayString))
        }
    }


    /// For a date *with* an existing completion doc
    private func viewForExistingCompletion(_ completion: Completion, dayString: String) -> some View {
        // 1) Parse dayString → local Date
        guard let localDate = parseLocalMidnight(dayString) else {
            // Fallback if dayString can't be parsed
            return AnyView(Text("Error: invalid dayString").foregroundColor(.red))
        }

        // 2) Compare with 'today'
        let today = Calendar.current.startOfDay(for: Date())
        
        let isXDaysCompleted = (goal.frequency == .xDays) &&
                              (completedCompletionsCount >= goal.requiredCompletions)
        
        if isXDaysCompleted && (completion.status != .verified && completion.status != .refunded) {
            return AnyView(Text("Completed")
                .italic()
                .foregroundColor(.gray))
        }

        switch completion.status {
        case .nonSubmitted:
            if localDate < today {
                // Past date => missed
                return AnyView(Text("Missed")
                    .italic()
                    .foregroundColor(.orange))
            } else if Calendar.current.isDate(localDate, inSameDayAs: today) {
                // It's "today" => show "Verify" button
                return AnyView(
                    Button("Verify") {
                        selectedDayString = dayString
                        showingCompletionModal = true
                    }
                    .buttonStyle(BorderlessButtonStyle())
                )
            } else {
                // Future => upcoming
                return AnyView(Text("Upcoming")
                    .font(.caption)
                    .foregroundColor(.gray))
            }

        case .pendingVerification:
            return AnyView(Text("Pending Verification").italic().foregroundColor(.gray))
        case .verified:
            return AnyView(
                HStack(spacing: 8) { // Increased spacing for better appearance
                    Text("Verified")
                        .italic()
                        .foregroundColor(.green)
                    CustomLoader(
                        size: 12, // Increased size
                        lineWidth: 1, // Thicker line for visibility
                        color: .green,
                        rotationDuration: 3 // Slower rotation
                    )
                }
            )
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
    private func viewForNoCompletionDoc(_ dayString: String) -> some View {
        guard let localDate = parseLocalMidnight(dayString) else {
            return AnyView(Text("Error: invalid dayString").foregroundColor(.red))
        }

        let today = Calendar.current.startOfDay(for: Date())
        
        let isXDaysCompleted = (goal.frequency == .xDays) &&
                              (completedCompletionsCount >= goal.requiredCompletions)
        
        if isXDaysCompleted {
            return AnyView(Text("Completed")
                .italic()
                .foregroundColor(.gray))
        }

        if localDate < today {
            // Past => missed
            return AnyView(
                Text("Missed")
                    .italic()
                    .foregroundColor(.orange)
            )
        } else if Calendar.current.isDate(localDate, inSameDayAs: today) {
            // Present => show "Verify"
            return AnyView(
                Button("Verify") {
                    selectedDayString = dayString
                    showingCompletionModal = true
                }
                .buttonStyle(BorderlessButtonStyle())
            )
        } else {
            // Future => upcoming
            return AnyView(
                Text("Upcoming")
                    .font(.caption)
                    .foregroundColor(.gray)
            )
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
    private func canCompleteForDate(_ dayString: String) -> Bool {
        guard let localDate = parseLocalMidnight(dayString) else {
            return false
        }

        // 1) Check if dayString is "today"
        let today = Calendar.current.startOfDay(for: Date())
        let isToday = Calendar.current.isDate(localDate, inSameDayAs: today)

        // 2) See if we have a completion doc for that dayString
        let completionExists = (completionForDayString(dayString) != nil)

        switch goal.frequency {
        case .daily:
            return isToday && !completionExists

        case .weekdays:
            return isToday
                && !Calendar.current.isDateInWeekend(localDate)
                && !completionExists

        case .weekends:
            return isToday
                && Calendar.current.isDateInWeekend(localDate)
                && !completionExists

        case .xDays:
            // Count how many completions are verified or refunded
            let completedCount = (viewModel.completionsByGoal[goal.id ?? ""] ?? [])
                .filter { $0.status == .verified || $0.status == .refunded }
                .count

            return isToday
                && (completedCount < goal.requiredCompletions)
                && !completionExists
        }
    }

    
    private func getDayStringsRange() -> [String] {
        let calendar = Calendar.current
        let localStart = calendar.startOfDay(for: goal.startDate)
        let localEnd = calendar.startOfDay(for: goal.endDate)
        
        // Determine the total number of days between start and end dates.
        guard let totalDays = calendar.dateComponents([.day], from: localStart, to: localEnd).day else {
            return []
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        
        // Build an array of all dates from start to end.
        var allDates: [Date] = []
        for offset in 0...totalDays {
            if let thisDay = calendar.date(byAdding: .day, value: offset, to: localStart) {
                allDates.append(thisDay)
            }
        }
        
        // Filter dates based on frequency.
        let filteredDates: [Date]
        switch goal.frequency {
        case .daily, .xDays:
            filteredDates = allDates
        case .weekdays:
            filteredDates = allDates.filter { !calendar.isDateInWeekend($0) }
        case .weekends:
            filteredDates = allDates.filter { calendar.isDateInWeekend($0) }
        }
        
        // Convert the filtered dates to strings.
        let dateStrings = filteredDates.map { formatter.string(from: $0) }
        
        return dateStrings
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
    
    private var completedCompletionsCount: Int {
        guard let goalId = goal.id,
              let completions = viewModel.completionsByGoal[goalId] else {
            return 0
        }
        return completions.filter {
            $0.status == .verified || $0.status == .refunded
        }.count
    }
    
    /// Refresh the local `goal` data from the viewModel so we stay in sync.
    /// This updates the goal’s main fields (title, totalAmount, etc.), but not sub-collection completions.
    private func refreshGoal() {
        guard let goalId = goal.id else { return }
        if let updatedGoal = viewModel.getGoal(withId: goalId) {
            self.goal = updatedGoal
        }
    }
    
    private func parseLocalMidnight(_ dayString: String) -> Date? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current  // or omit since .current is default
        return df.date(from: dayString)
    }
}

struct CustomLoader: View {
    @State private var isAnimating = false
    
    // Parameters to adjust size and rotation speed
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2
    var color: Color = .green
    var rotationDuration: Double = 2 // Duration for a full 360° rotation
    
    var body: some View {
        Circle()
            .trim(from: 0.0, to: 0.7) // Creates a partial circle for the spinner effect
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
            .animation(
                Animation.linear(duration: rotationDuration)
                    .repeatForever(autoreverses: false),
                value: isAnimating
            )
            .onAppear {
                self.isAnimating = true
            }
    }
}
