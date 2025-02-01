import SwiftUI
import FirebaseFirestore // Add this

struct AdminPhotoVerificationView: View {
    let ref: DocumentReference // Changed from completion
    @ObservedObject var viewModel: AdminViewModel
    @Environment(\.dismiss) private var dismiss
    @StateObject var goalVM = GoalViewModel()
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var completion: Completion? // Added to load from ref
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let image = image, let completion = completion {
                contentView(image: image, completion: completion)
            } else {
                Text("Failed to load data")
                    .foregroundColor(.red)
            }
        }
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        // First load completion from reference
        do {
            let snapshot = try await ref.getDocument()
            completion = try snapshot.data(as: Completion.self)
            
            // Then load image if available
            if let urlString = completion?.verificationPhotoUrl,
               let url = URL(string: urlString) {
                let (data, _) = try await URLSession.shared.data(from: url)
                image = UIImage(data: data)
            }
        } catch {
            print("Loading failed: \(error)")
        }
        isLoading = false
    }
    
    // Updated to take completion parameter
    private func contentView(image: UIImage, completion: Completion) -> some View {
        VStack(spacing: 20) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 400)
            
            if let explanation = completion.explanation {
                Text(explanation)
                    .padding()
                    .cornerRadius(8)
            }
            
            HStack(spacing: 20) {
                Button("Reject") {
                    viewModel.rejectSubmission(ref) // Changed to use ref
                    dismiss()
                }
                .buttonStyle(RejectButtonStyle())
                
                Button("Verify") {
                    print("DEBUG: Verify button tapped.")
                    
                    // First update the completion's status to 'verified'
                    viewModel.approveSubmission(ref)
                    print("DEBUG: Called approveSubmission with ref: \(ref.path)")
                    
                    // Get the parent goal document from the completion's reference.
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
                              let goal = try? snapshot.data(as: Goal.self) else {
                            print("DEBUG: Goal document not found or could not be decoded.")
                            dismiss()
                            return
                        }
                        print("DEBUG: Successfully fetched goal document: \(goal)")
                        
                        // Extract the owner (user) ID from the document path.
                        if let ownerDocRef = goalDocRef.parent.parent {
                            let ownerId = ownerDocRef.documentID
                            print("DEBUG: Retrieved owner document reference: \(ownerDocRef.path) with ownerId: \(ownerId)")
                            
                            let refundDayString = self.completion?.dateString ?? ""
                            print("DEBUG: Will call triggerRefund for dayString: \(refundDayString)")
                            
                            // Use the retained goalVM instead of creating a new one.
                            goalVM.triggerRefund(for: goal, dayString: refundDayString, ownerId: ownerId) { result in
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
