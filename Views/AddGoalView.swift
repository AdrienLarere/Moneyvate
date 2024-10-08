import SwiftUI
import UIKit
import Stripe
import StripePaymentSheet
import Combine
import PassKit

struct AddGoalView: View {
    @EnvironmentObject var viewModel: GoalViewModel
    @EnvironmentObject var userManager: UserManager
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
    @State private var showingApplePay = false
    @State private var applePayRequest: PKPaymentRequest?
    
    private var currencySymbol: String {
        let locale = Locale(identifier: Locale.current.identifier)
        return CurrencyHelper.currencySymbol(for: userManager.currentCurrency) ?? locale.currencySymbol ?? "$"
    }
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
                        Text(currencySymbol)
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
                            Button("Pay \(CurrencyHelper.format(amount: calculateTotalAmount(), currencyCode: userManager.currentCurrency))") {
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
                        switch result {
                        case .completed:
                            self.handlePaymentResult(success: true, error: nil)
                        case .failed(let error):
                            self.handlePaymentResult(success: false, error: error.localizedDescription)
                        case .canceled:
                            self.handlePaymentResult(success: false, error: "Payment canceled by user")
                        }
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
                    if self.alertTitle == "Success" {
                        self.isPresented = false
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
        
        paymentViewModel.createPaymentIntent(amount: amount, currencyCode: userManager.currentCurrency) { success in
            DispatchQueue.main.async {
                if success {
                    print("Payment intent created successfully")
                    self.showingPaymentSheet = true
                } else {
                    print("Failed to create payment intent")
                    self.showAlert(title: "Error", message: "Failed to prepare payment")
                }
            }
        }
    }

    private func setupApplePayRequest(amount: Int) {
        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = "merchant.com.moneyvate" // Replace with your merchant ID
        paymentRequest.supportedNetworks = [.visa, .masterCard, .amex]
        
        if #available(iOS 17.0, *) {
            paymentRequest.merchantCapabilities = .threeDSecure
        } else {
            paymentRequest.merchantCapabilities = .capability3DS
        }
        
        paymentRequest.countryCode = "US" // Replace with your country code
        paymentRequest.currencyCode = "USD" // Replace with your currency code
        paymentRequest.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "Moneyvate Goal", amount: NSDecimalNumber(value: Double(amount) / 100.0))
        ]
        
        self.applePayRequest = paymentRequest
        self.showingApplePay = true
    }
    
    private func handlePaymentResult(success: Bool, error: String?) {
        DispatchQueue.main.async {
            self.showingPaymentSheet = false
            self.showingApplePay = false
            
            if success {
                self.addGoal()
                self.showAlert(title: "Success", message: "Payment completed and goal added!")
                self.isPresented = false
            } else {
                self.showAlert(title: "Payment Failed", message: error ?? "Unknown error occurred")
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
              currency: userManager.currentCurrency,
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
