import SwiftUI

struct GoalDetailView: View {
    @ObservedObject var viewModel: GoalViewModel
    @State private var showingCompletionModal = false
    @State private var selectedDate: Date?
    @Binding var goal: Goal

    var body: some View {
        List {
            Section(header: Text("Goal Details")) {
                Text("Title: \(goal.title)")
                Text("Frequency: \(goal.frequency.rawValue)")
                Text("Amount per Success: £\(goal.amountPerSuccess, specifier: "%.2f")")
                Text("Total Amount: £\(goal.totalAmount, specifier: "%.2f")")
                Text("Earned Amount: £\(goal.earnedAmount, specifier: "%.2f")")
            }
            .onAppear(perform: refreshGoal)
            
            Section(header: Text("Progress")) {
                ForEach(getDateRange(), id: \.self) { date in
                    HStack {
                        Text(formatDate(date))
                        Spacer()
                        if let completion = goal.completionDates[date] {
                            completionStatusView(for: completion)
                        } else if isToday(date) || isPast(date) {
                            Button("Complete") {
                                selectedDate = date
                                showingCompletionModal = true
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        } else {
                            Text("Upcoming")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .navigationTitle(goal.title)
        .sheet(isPresented: $showingCompletionModal) {
            if let date = selectedDate {
                CompletionModalView(viewModel: viewModel, goal: $goal, date: date)
            }
        }
    }
    
    private func completionStatusView(for completion: Completion) -> some View {
        switch completion.status {
        case .pendingVerification:
            return Image(systemName: "clock.fill")
                .foregroundColor(.orange)
        case .verified:
            return Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .refunded:
            return Image(systemName: "dollarsign.circle.fill")
                .foregroundColor(.blue)
        case .rejected:
            return Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
    
    private func getDateRange() -> [Date] {
        guard let days = Calendar.current.dateComponents([.day], from: goal.startDate, to: goal.endDate).day else {
            return []
        }
        return (0...days).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: goal.startDate) }
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
        if let updatedGoal = viewModel.goals.first(where: { $0.id == goal.id }) {
            goal = updatedGoal
        }
    }
}
