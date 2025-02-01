import SwiftUI
import FirebaseFirestore

struct AdminPhotoVerificationView: View {
    let ref: DocumentReference // Reference to the completion document.
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject var goalVM = GoalViewModel() // For refund logic.
    
    @State private var goal: Goal?           // Fetched goal document.
    @State private var image: UIImage?         // Loaded image.
    @State private var isLoading = true
    @State private var completion: Completion? // Fetched completion document.
    @State private var loadErrorMessage: String? // Error message if image fails.
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let goal = goal, let _ = completion {
                // Always show the goal title and then either the image or an error message.
                contentViewForGoal()
            } else {
                Text("Failed to load data")
                    .foregroundColor(.red)
            }
        }
        .task {
            await loadData()
        }
    }
    
    // Load completion, goal, and image.
    private func loadData() async {
        do {
            // 1. Fetch the completion document.
            let snapshot = try await ref.getDocument()
            completion = try snapshot.data(as: Completion.self)
            
            // 2. Fetch the goal document from the parent's parent.
            if let goalDocRef = ref.parent.parent {
                let goalSnapshot = try await goalDocRef.getDocument()
                goal = try goalSnapshot.data(as: Goal.self)
            }
            
            // 3. Attempt to load the image.
            if let urlString = completion?.verificationPhotoUrl,
               let url = URL(string: urlString) {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    image = uiImage
                } else {
                    loadErrorMessage = "Link missing or broken"
                }
            } else {
                loadErrorMessage = "Link missing or broken"
            }
        } catch {
            print("Loading failed: \(error)")
            loadErrorMessage = "Link missing or broken"
        }
        isLoading = false
    }
    
    // A view that always displays the goal title at the top.
    // If the image is loaded, it shows the image; otherwise, it shows an error message.
    private func contentViewForGoal() -> some View {
        VStack(spacing: 20) {
            // Display the goal title at the top.
            if let goalTitle = goal?.title {
                Text(goalTitle)
                    .font(.title)
                    .fontWeight(.bold)
            }
            
            // Display image if available; otherwise, show an error message.
            if let image = image, let _ = completion {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 400)
            } else {
                Text(loadErrorMessage ?? "Link missing or broken")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            // Display the explanation if available.
            if let explanation = completion?.explanation, !explanation.isEmpty {
                Text(explanation)
                    .padding()
                    .cornerRadius(8)
            }
            
            // Action buttons.
            HStack(spacing: 20) {
                Button("Reject") {
                    viewModel.rejectSubmission(ref)
                    dismiss()
                }
                .buttonStyle(RejectButtonStyle())
                
                Button("Verify") {
                    print("DEBUG: Verify button tapped.")
                    
                    // Update the completion's status.
                    viewModel.approveSubmission(ref)
                    print("DEBUG: Called approveSubmission with ref: \(ref.path)")
                    
                    // Fetch the goal document for refund logic.
                    guard let goalDocRef = ref.parent.parent else {
                        print("DEBUG: Could not determine goal document reference.")
                        dismiss()
                        return
                    }
                    
                    print("DEBUG: Retrieved goal document reference: \(goalDocRef.path)")
                    
                    goalDocRef.getDocument { snapshot, error in
                        if let error = error {
                            print("DEBUG: Error fetching goal document: \(error.localizedDescription)")
                            dismiss()
                            return
                        }
                        guard let snapshot = snapshot, snapshot.exists,
                              let fetchedGoal = try? snapshot.data(as: Goal.self) else {
                            print("DEBUG: Goal document not found or could not be decoded.")
                            dismiss()
                            return
                        }
                        print("DEBUG: Successfully fetched goal document: \(fetchedGoal)")
                        
                        // Extract the owner (user) ID.
                        if let ownerDocRef = goalDocRef.parent.parent {
                            let ownerId = ownerDocRef.documentID
                            print("DEBUG: Retrieved owner document reference: \(ownerDocRef.path) with ownerId: \(ownerId)")
                            
                            let refundDayString = self.completion?.dateString ?? ""
                            print("DEBUG: Will call triggerRefund for dayString: \(refundDayString)")
                            
                            // Trigger refund using the retained goalVM.
                            goalVM.triggerRefund(for: fetchedGoal, dayString: refundDayString, ownerId: ownerId) { result in
                                DispatchQueue.main.async {
                                    switch result {
                                    case .success:
                                        print("DEBUG: Refund processed successfully.")
                                    case .failure(let error):
                                        print("DEBUG: Refund failed: \(error.localizedDescription)")
                                    }
                                }
                            }
                        } else {
                            print("DEBUG: Could not determine owner document reference.")
                        }
                        
                        print("DEBUG: Dismissing admin view.")
                        dismiss()
                    }
                }
                .buttonStyle(VerifyButtonStyle())
            }
            .padding(.top)
        }
        .padding()
    }
}

struct VerifyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(width: 120)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

struct RejectButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(width: 120)
            .background(Color.red)
            .foregroundColor(.white)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}
