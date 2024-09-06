import SwiftUI

struct AddGoalView: View {
    @EnvironmentObject var viewModel: GoalViewModel
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var frequency: Goal.Frequency = .daily
    @State private var amountPerSuccess = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(86400 * 7)
    @State private var requiredCompletions = 1
    @State private var verificationMethod: Goal.VerificationMethod = .selfVerify
    @State private var agreementChecked = false
    
    // Assuming USD for this example. In a real app, you'd get this from user settings or localization.
    private let currency = "$"
    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Goal Details")) {
                    TextField("Goal Title", text: $title)
                    Picker("Frequency", selection: $frequency) {
                        ForEach(Goal.Frequency.allCases) { frequency in
                            Text(frequency.rawValue).tag(frequency)
                        }
                    }
                    HStack {
                        Text(currency)
                        TextField("Amount per Success", text: $amountPerSuccess)
                            .keyboardType(.decimalPad)
                    }
                }
                
                Section(header: Text("Date Range")) {
                    DatePicker("Start Date", selection: $startDate, in: today..., displayedComponents: .date)
                    DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                }
                
                if frequency == .xDays {
                    Section(header: Text("Required Completions")) {
                        Stepper(value: $requiredCompletions, in: 1...maxCompletions) {
                            Text("\(requiredCompletions) day\(requiredCompletions == 1 ? "" : "s")")
                        }
                    }
                }
                
                Section(header: Text("Verification")) {
                    Picker("Verification Method", selection: $verificationMethod) {
                        ForEach(Goal.VerificationMethod.allCases) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                }
                
                Section {
                    Toggle(isOn: $agreementChecked) {
                        Text("If I miss my daily goal, I will not get that day's money back.")
                            .padding(.leading, 10)
                    }
                    .toggleStyle(CheckboxToggleStyle())
                    
                    Button("Pay \(currency)\(calculateTotalAmount(), specifier: "%.2f")") {
                        addGoal()
                    }
                    .disabled(!isFormValid)
                }
            }
            .navigationTitle("Add New Goal")
            .onChange(of: startDate) { _ in updateRequiredCompletions() }
            .onChange(of: endDate) { _ in updateRequiredCompletions() }
        }
        .onAppear {
            // Ensure startDate is set to today if it's in the past
            if startDate < today {
                startDate = today
            }
        }
    }
    
    private func updateRequiredCompletions() {
        if frequency == .xDays {
            requiredCompletions = min(requiredCompletions, maxCompletions)
        }
    }
    
    private var maxCompletions: Int {
        max(1, Calendar.current.numberOfDaysBetween(startDate, and: endDate))
    }
    
    private var isFormValid: Bool {
        !title.isEmpty &&
        !amountPerSuccess.isEmpty &&
        Double(amountPerSuccess) != nil &&
        agreementChecked &&
        calculateTotalAmount() > 0  // This ensures the goal has at least one completion
    }
    
    private func calculateTotalAmount() -> Double {
        guard let amountPerSuccess = Double(amountPerSuccess) else { return 0 }
        let days: Int
        switch frequency {
        case .daily:
            days = Calendar.current.numberOfDaysBetween(startDate, and: endDate)
            print("Days for daily goal: \(days)")
        case .weekdays:
            days = countWeekdays(from: startDate, to: endDate)
            print("Weekdays for goal: \(days)")
        case .weekends:
            days = countWeekends(from: startDate, to: endDate)
            print("Weekend days for goal: \(days)")
        case .xDays:
            days = min(requiredCompletions, maxCompletions)
            print("Days for xDays goal: \(days)")
        }
        let totalAmount = Double(days) * amountPerSuccess
        print("Total amount: \(totalAmount)")
        return totalAmount
    }
    
    private func countWeekdays(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: start)
        let endDate = calendar.startOfDay(for: end)
        var count = 0
        var current = startDate
        
        while current <= endDate {
            let weekday = calendar.component(.weekday, from: current)
            if (2...6).contains(weekday) {
                count += 1
            }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        
        return count
    }

    private func countWeekends(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let startDate = calendar.startOfDay(for: start)
        let endDate = calendar.startOfDay(for: end)
        var count = 0
        var current = startDate
        
        while current <= endDate {
            let weekday = calendar.component(.weekday, from: current)
            if weekday == 1 || weekday == 7 {
                count += 1
            }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        
        return count
    }
    
    private func addGoal() {
        if let amountPerSuccess = Double(amountPerSuccess) {
            let requiredCompletions: Int
            switch frequency {
            case .daily:
                requiredCompletions = Calendar.current.numberOfDaysBetween(startDate, and: endDate)
            case .weekdays:
                requiredCompletions = countWeekdays(from: startDate, to: endDate)
            case .weekends:
                requiredCompletions = countWeekends(from: startDate, to: endDate)
            case .xDays:
                requiredCompletions = self.requiredCompletions
            }
            viewModel.addGoal(title: title,
                              frequency: frequency,
                              amountPerSuccess: amountPerSuccess,
                              startDate: startDate,
                              endDate: endDate,
                              requiredCompletions: requiredCompletions,
                              verificationMethod: verificationMethod)
            isPresented = false
        }
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .foregroundColor(configuration.isOn ? .blue : .gray)
                .onTapGesture { configuration.isOn.toggle() }
            configuration.label
        }
    }
}

extension Calendar {
    func numberOfDaysBetween(_ from: Date, and to: Date) -> Int {
        let fromDate = startOfDay(for: from) // <-- Normalize dates to start of day
        let toDate = startOfDay(for: to)
        let numberOfDays = dateComponents([.day], from: fromDate, to: toDate)
        return numberOfDays.day! + 1 // <-- Add 1 to include both start and end dates
    }
}
