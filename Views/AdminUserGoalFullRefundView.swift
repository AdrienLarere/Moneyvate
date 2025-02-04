import SwiftUI

struct AdminUserGoalFullRefundView: View {
    // Change from constant to mutable state variable so we can update it.
    @State var goal: Goal
    @StateObject private var viewModel = GoalViewModel()
    @State private var refundStatusMessage: String?
    @State private var isRefunding = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text(goal.title)
                .font(.title)
                .fontWeight(.bold)
            
            // Display different values if the goal has been manually refunded.
            if goal.manuallyRefunded ?? false {
                Text("Total Amount: \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                Text("Earned Amount: \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                Text("Remaining: \(CurrencyHelper.format(amount: 0, currencyCode: goal.currency ?? "USD"))")
            } else {
                Text("Total Amount: \(CurrencyHelper.format(amount: goal.totalAmount, currencyCode: goal.currency ?? "USD"))")
                let earned = viewModel.earnedAmount(for: goal)
                Text("Earned Amount: \(CurrencyHelper.format(amount: earned, currencyCode: goal.currency ?? "USD"))")
                let remaining = goal.totalAmount - earned
                Text("Remaining: \(CurrencyHelper.format(amount: remaining, currencyCode: goal.currency ?? "USD"))")
            }
            
            if isRefunding {
                ProgressView("Refunding...")
            }
            
            if let message = refundStatusMessage {
                Text(message)
                    .foregroundColor(message.contains("successful") ? .green : .red)
            }
            
            // If the goal is manually refunded, show the status instead of the button.
            if goal.manuallyRefunded ?? false {
                Text("Goal fully refunded")
                    .foregroundColor(.green)
                    .font(.headline)
            } else if !isRefunding {
                Button("Refund Remaining Amount") {
                    triggerFullRefund()
                }
                .disabled(isRefunding)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Refund Goal")
    }
    
    private func triggerFullRefund() {
        isRefunding = true
        viewModel.triggerFullRefund(for: goal) { result in
            DispatchQueue.main.async {
                isRefunding = false
                switch result {
                case .success:
                    refundStatusMessage = "Refund successful"
                    // Now mark the goal as manually refunded.
                    viewModel.markGoalAsManuallyRefunded(goal) { updateResult in
                        DispatchQueue.main.async {
                            switch updateResult {
                            case .success:
                                print("Goal marked as manually refunded.")
                                // Update local state so that the UI reflects the change:
                                goal.manuallyRefunded = true
                            case .failure(let error):
                                print("Failed to mark goal as manually refunded: \(error.localizedDescription)")
                            }
                        }
                    }
                case .failure(let error):
                    refundStatusMessage = "Refund failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
