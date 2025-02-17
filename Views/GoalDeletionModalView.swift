import SwiftUI

struct GoalDeletionModalView: View {
    // Bind the goal so we can update it after deletion.
    @Binding var goal: Goal
    @EnvironmentObject var viewModel: GoalViewModel
    @Environment(\.dismiss) var dismiss
    
    // State for deletion process
    @State private var isDeleting = false
    @State private var deletionStatusMessage: String?

    // Compute whether deletion is within 24 hours.
    private var isWithin24Hours: Bool {
        let calendar = Calendar.current
        // Convert both dates to local midnight for an accurate comparison.
        let now = Date()
        let start = calendar.startOfDay(for: goal.startDate)
        let components = calendar.dateComponents([.hour], from: start, to: now)
        let hoursPassed = components.hour ?? 0
        return hoursPassed < 24
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Goal Deletion")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Deleting a goal could be an easy way to avoid its completion.\n\nWe want to prevent this hack, but we also want our tech to be fair and forgiving.\n\nThis is our solution:\n\nIf you delete your goal within 24 hours of its creation or if it's in the future, you'll receive a full refund along with the deletion.\n\nBeyond the 24 hours mark however, you will receive a 10% penalty, such that your total refund will only be worth 90% of the total amount paid.")
                    .multilineTextAlignment(.center)
                    .padding()
                
                if isDeleting {
                    ProgressView("Deleting...")
                }
                
                if let message = deletionStatusMessage {
                    Text(message)
                        .foregroundColor(message.contains("successful") ? .green : .red)
                }
                
                if !isDeleting {
                    if isWithin24Hours {
                        Button(action: {
                            triggerDeletion(fullRefund: true)
                        }) {
                            Text("Full Refund + Deletion")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    } else {
                        Button(action: {
                            triggerDeletion(fullRefund: false)
                        }) {
                            Text("90% Refund + Deletion")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Delete Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func triggerDeletion(fullRefund: Bool) {
        if fullRefund {
            // Within 24 hours: trigger full refund deletion.
            viewModel.triggerFullRefund(for: goal) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        completeDeletion()
                    case .failure(let error):
                        print("Full refund deletion failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // After 24 hours: trigger late deletion refund.
            viewModel.triggerLateDeletionRefund(for: goal) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        completeDeletion()
                    case .failure(let error):
                        print("Late deletion refund failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func completeDeletion() {
        // Mark the goal as deleted by setting isDeleted and deletionDate.
        viewModel.markGoalAsDeleted(goal) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Goal marked as deleted.")
                    // Update local state:
                    goal.isDeleted = true
                    goal.deletionDate = Date()
                    dismiss()
                case .failure(let error):
                    print("Failed to mark goal as deleted: \(error.localizedDescription)")
                }
            }
        }
    }
}
