import SwiftUI

struct GoalDeletionModalView: View {
    @Binding var goal: Goal
    @EnvironmentObject var viewModel: GoalViewModel
    @Environment(\.dismiss) var dismiss

    @State private var isDeleting = false
    @State private var deletionStatusMessage: String?

    private var isWithin24Hours: Bool {
        let calendar = Calendar.current
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

                // 1) If currently deleting, show a progress view
                if isDeleting {
                    ProgressView("Deleting...")
                }

                // 2) Show optional status message
                if let message = deletionStatusMessage {
                    Text(message)
                        .foregroundColor(message.contains("successful") ? .green : .red)
                }

                // 3) Only show delete buttons if not deleting
                if !isDeleting {
                    if isWithin24Hours {
                        Button {
                            isDeleting = true
                            triggerDeletion(fullRefund: true)
                        } label: {
                            HStack {
                                Spacer()          // push text center
                                Text("Full Refund + Deletion")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Spacer()          // push text center
                            }
                            .padding()
                            .background(Color.red)
                            .cornerRadius(10)
                        }

                    } else {
                        Button("90% Refund + Deletion") {
                            isDeleting = true
                            triggerDeletion(fullRefund: false)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
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
                    .disabled(isDeleting) // disable if currently deleting
                }
            }
        }
    }

    private func triggerDeletion(fullRefund: Bool) {
        // We'll show the loader by setting isDeleting=true above.

        if fullRefund {
            viewModel.triggerFullRefund(for: goal) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        completeDeletion()
                    case .failure(let error):
                        isDeleting = false
                        self.deletionStatusMessage = "Full refund deletion failed: \(error.localizedDescription)"
                        print("Full refund deletion failed: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            viewModel.triggerLateDeletionRefund(for: goal) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        completeDeletion()
                    case .failure(let error):
                        isDeleting = false
                        self.deletionStatusMessage = "Late deletion refund failed: \(error.localizedDescription)"
                        print("Late deletion refund failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func completeDeletion() {
        viewModel.markGoalAsDeleted(goal) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("Goal marked as deleted.")
                    goal.isDeleted = true
                    goal.deletionDate = Date()
                    dismiss()  // close modal
                case .failure(let error):
                    isDeleting = false
                    self.deletionStatusMessage = "Failed to mark goal as deleted: \(error.localizedDescription)"
                    print("Failed to mark goal as deleted: \(error.localizedDescription)")
                }
            }
        }
    }
}
