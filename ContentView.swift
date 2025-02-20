import SwiftUI
import FirebaseAuth
import FirebaseStorage

struct ContentView: View {
    @EnvironmentObject var viewModel: GoalViewModel
    @EnvironmentObject var userManager: UserManager

    // We'll store actual objects
    @State private var refundedPIs: [RefundedPaymentIntent] = []
    @State private var showRefundAlert = false
    
    @State private var isShowingSignUp = false

    var body: some View {
        // 1) Determine the user's chosen theme
        let appColorScheme = mapThemeToColorScheme(userManager.userProfile?.themeMode ?? "system")

        return Group {
            if userManager.isAuthenticated {
                if userManager.isEmailVerified {
                    mainView
                } else {
                    EmailVerificationView()
                }
            } else {
                if userManager.isNewUser {
                    EmailVerificationView()
                } else {
                    signInView
                }
            }
        }
        // 2) Apply the color scheme
        .preferredColorScheme(appColorScheme)
        // 3) The rest of your logic
        .onChange(of: userManager.isAuthenticated) { oldValue, newValue in
            if newValue {
                DispatchQueue.main.async {
                    self.viewModel.fetchGoals()
                }
                
                // Check/refund missing PaymentIntents
                userManager.checkAndRefundMissingGoalPayments { refundedObjects in
                    if !refundedObjects.isEmpty {
                        DispatchQueue.main.async {
                            self.refundedPIs = refundedObjects
                            self.showRefundAlert = true
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.viewModel.clearGoals()
                }
            }
        }
        .alert("Payment Refunded", isPresented: $showRefundAlert) {
            Button("OK") { }
        } message: {
            Text(refundMessage)
        }
    }
    
    // Helpers
    
    private func mapThemeToColorScheme(_ themeMode: String) -> ColorScheme? {
        switch themeMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            // system or unknown => nil => use system setting
            return nil
        }
    }
    
    private var refundMessage: String {
        // Sum all amounts and convert to a float
        let totalCents = refundedPIs.reduce(0) { $0 + $1.amount }
        let currency = refundedPIs.first?.currency.uppercased() ?? "USD" // or adapt
        let totalDecimal = Double(totalCents) / 100.0
        
        return """
        
        Something went wrong for a goal you attempted to create:
        
        The payment went through but the goal was not created.
        
        As such, we've automatically refunded the full payment of \(String(format: "%.2f", totalDecimal)) \(currency).
        
        Your money is already on its way back to you.
        
        We apologize for the inconvenience,
        
        The Moneyvate Team
        """
    }
    
    private var signInView: some View {
        SignInView(isShowingSignUp: $isShowingSignUp)
            .sheet(isPresented: $isShowingSignUp) {
                SignUpView()
            }
    }
    
    // The only logic: if admin => AdminSegmentedView, else => GoalsView
    private var mainView: some View {
        Group {
            if userManager.userProfile?.isAdmin == true {
                // Show the Admin layout
                AdminSegmentedView()
                    .environmentObject(viewModel)
                    .environmentObject(userManager)
            } else {
                // Show the normal goals layout
                GoalsView()
                    .environmentObject(viewModel)
                    .environmentObject(userManager)
            }
        }
    }
}
