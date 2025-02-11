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
        Group {
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
        // The alert
        .alert("Payment Refunded", isPresented: $showRefundAlert) {
            Button("OK") { }
        } message: {
            Text(refundMessage)
        }
    }
    
    // MARK: - Refund Alert Message
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
