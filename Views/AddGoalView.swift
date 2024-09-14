import SwiftUI
import UIKit
import Stripe
import StripePaymentSheet
import Combine

struct AddGoalView: View {
    @EnvironmentObject var viewModel: GoalViewModel
    @StateObject private var paymentViewModel = PaymentViewModel()
    @Binding var isPresented: Bool
    @State private var title = ""
    @State private var frequency: Goal.Frequency = .daily
    @State private var amountPerSuccess = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(86400 * 7)
    @State private var requiredCompletions = 1
    @State private var verificationMethod: Goal.VerificationMethod = .selfVerify
    @State private var agreementChecked = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingPaymentSheet = false
    
    private let currency = "$"
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    
    private let debouncer = Debouncer(delay: 0.5)
    
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
                    
                    Section {
                        if paymentViewModel.isLoading {
                            ProgressView("Preparing payment...")
                        } else if let errorMessage = paymentViewModel.errorMessage {
                            Text(errorMessage)
                                .foregroundColor(.red)
                        } else {
                            Button("Pay \(currency)\(calculateTotalAmount(), specifier: "%.2f")") {
                                initiatePayment()
                            }
                            .disabled(!isFormValid || !paymentViewModel.isNetworkAvailable)
                        }
                    }
                }
            }
            .navigationTitle("Add New Goal")
        }
        .onAppear {
            if startDate < today {
                startDate = today
            }
        }
        .sheet(isPresented: $showingPaymentSheet) {
            if let paymentSheet = paymentViewModel.stripePaymentSheet {
                ZStack {
                    PaymentProcessingView()

                    PaymentSheetUI(paymentSheet: paymentSheet) { result in
                        handlePaymentResult(result)
                        showingPaymentSheet = false
                    }
                }
            } else {
                PaymentProcessingView()
            }
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"), action: {
                    // Dismiss the AddGoalView after the alert is dismissed
                    if alertTitle == "Success" {
                        isPresented = false
                    }
                })
            )
        }
    }
    
    private var isFormValid: Bool {
        !title.isEmpty &&
        !amountPerSuccess.isEmpty &&
        Double(amountPerSuccess) ?? 0 > 0 &&
        agreementChecked &&
        calculateTotalAmount() > 0
    }
    
    private var maxCompletions: Int {
        max(1, Calendar.current.numberOfDaysBetween(startDate, and: endDate))
    }
    
    private func calculateTotalAmount() -> Double {
        guard let amountPerSuccess = Double(amountPerSuccess) else { return 0 }
        let days: Int
        switch frequency {
        case .daily:
            days = Calendar.current.numberOfDaysBetween(startDate, and: endDate)
        case .weekdays:
            days = countWeekdays(from: startDate, to: endDate)
        case .weekends:
            days = countWeekends(from: startDate, to: endDate)
        case .xDays:
            days = min(requiredCompletions, Calendar.current.numberOfDaysBetween(startDate, and: endDate))
        }
        return Double(days) * amountPerSuccess
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
    
    private func initiatePayment() {
        print("Initiating payment process")
        let amount = Int(calculateTotalAmount() * 100)
        print("Calculated amount: \(amount)")
        paymentViewModel.createPaymentIntent(amount: amount) { success in
            DispatchQueue.main.async {
                if success {
                    print("Payment sheet prepared successfully")
                    self.showingPaymentSheet = true
                } else {
                    print("Failed to prepare payment sheet")
                    self.showAlert(title: "Error", message: "Failed to prepare payment sheet")
                }
            }
        }
    }

    private func handlePaymentResult(_ result: PaymentSheetResult) {
        DispatchQueue.main.async {
            self.showingPaymentSheet = false // Dismiss the payment sheet
            switch result {
            case .completed:
                print("Payment completed successfully")
                self.addGoal()
                self.showAlert(title: "Success", message: "Payment completed and goal added!")
            case .failed(let error):
                print("Payment failed with error: \(error.localizedDescription)")
                self.showAlert(title: "Payment Failed", message: error.localizedDescription)
            case .canceled:
                print("Payment canceled by user")
                self.showAlert(title: "Payment Canceled", message: "You've canceled the payment process.")
            }
        }
    }


    private func presentPaymentSheet() {
        if paymentViewModel.stripePaymentSheet != nil {
            print("stripePaymentSheet is available")
            showingPaymentSheet = true
        } else {
            print("Payment sheet not available.")
            showAlert(title: "Error", message: "Payment sheet not available.")
        }
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
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
              verificationMethod: verificationMethod,
              paymentIntentId: paymentViewModel.paymentIntentId) // Pass paymentIntentId
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

struct PaymentProcessingView: View {
    var body: some View {
        VStack {
            Text("Payment Processing")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 50)
            
            Text("Please use the payment form below")
                .font(.body)
                .foregroundColor(.gray)
                .padding(.top, 20)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

struct PaymentSheetView: UIViewControllerRepresentable {
    let paymentSheet: PaymentSheet
    let onCompletion: (PaymentSheetResult) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        paymentSheet.present(from: uiViewController) { result in
            onCompletion(result)
        }
    }
}

class Debouncer {
    private let delay: TimeInterval
    private var workItem: DispatchWorkItem?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    func debounce(action: @escaping () -> Void) {
        workItem?.cancel()
        workItem = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem!)
    }
}

extension Calendar {
    func numberOfDaysBetween(_ from: Date, and to: Date) -> Int {
        let fromDate = startOfDay(for: from)
        let toDate = startOfDay(for: to)
        let numberOfDays = dateComponents([.day], from: fromDate, to: toDate)
        return numberOfDays.day! + 1
    }
}
