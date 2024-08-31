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
                            Text("\(requiredCompletions) days")
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
        }
        .onAppear {
            // Ensure startDate is set to today if it's in the past
            if startDate < today {
                startDate = today
            }
        }
    }
    
    private var maxCompletions: Int {
        Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
    }
    
    private var isFormValid: Bool {
        !title.isEmpty && !amountPerSuccess.isEmpty && Double(amountPerSuccess) != nil && agreementChecked
    }
    
    private func calculateTotalAmount() -> Double {
        guard let amountPerSuccess = Double(amountPerSuccess) else { return 0 }
        let completions: Int
        switch frequency {
        case .daily:
            completions = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        case .weekdays:
            completions = countWeekdays(from: startDate, to: endDate)
        case .weekends:
            completions = countWeekends(from: startDate, to: endDate)
        case .xDays:
            completions = requiredCompletions
        }
        return Double(completions) * amountPerSuccess
    }
    
    private func countWeekdays(from start: Date, to end: Date) -> Int {
        var count = 0
        var current = start
        let calendar = Calendar.current
        
        while current <= end {
            let weekday = calendar.component(.weekday, from: current)
            if (2...6).contains(weekday) {
                count += 1
            }
            current = calendar.date(byAdding: .day, value: 1, to: current)!
        }
        
        return count
    }
    
    private func countWeekends(from start: Date, to end: Date) -> Int {
        var count = 0
        var current = start
        let calendar = Calendar.current
        
        while current <= end {
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
                requiredCompletions = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
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
