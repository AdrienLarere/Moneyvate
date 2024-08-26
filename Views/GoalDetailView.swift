import SwiftUI

struct GoalDetailView: View {
    @EnvironmentObject var viewModel: GoalViewModel
    let goal: Goal
    
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
                        if isToday(date) {
                            Image(systemName: goal.completionDates[date] ?? false ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(goal.completionDates[date] ?? false ? .green : .gray)
                                .onTapGesture {
                                    viewModel.toggleGoalCompletion(goal: goal, date: date)
                                }
                        } else if isPast(date) {
                            Image(systemName: goal.completionDates[date] ?? false ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(goal.completionDates[date] ?? false ? .green : .gray)
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
}
