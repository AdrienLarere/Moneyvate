import SwiftUI
import FirebaseStorage
import FirebaseFirestore

struct CompletionModalView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: GoalViewModel
    @Binding var goal: Goal
    let date: Date
    @State private var image: UIImage?
    @State private var isShowingImagePicker = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var completionStatus: Completion.CompletionStatus?
    var onCompletion: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 40)  // This will lower the header slightly
            
            Text(goal.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)  // This will center the text
            
            Text(formatDate(date))
                .font(.subheadline)
                .italic()
                .foregroundColor(.secondary)
            
            Spacer().frame(height: 175)
            
            if goal.verificationMethod == .selfVerify {
                Text("I have completed this goal")
                    .font(.body)  // Changed from .headline to remove bold
                    .padding(.bottom, 5)
                
                Button("Confirm") {
                    addCompletion()
                    print("Completion added, updated goal: \(goal)")
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isUploading)
            } else {
                // Photo verification UI remains the same
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                }

                Button(image == nil ? "Upload Photo" : "Change Photo") {
                    isShowingImagePicker = true
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)

                if image != nil {
                    Button("Submit") {
                        uploadPhotoAndAddCompletion()
                    }
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(isUploading)
                }
            }
            
            if let status = completionStatus {
                Text(statusText(for: status))
                    .foregroundColor(statusColor(for: status))
                    .padding(.top, 10)
            }

            if isUploading {
                ProgressView()
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
            
            Spacer()
        }
        .padding()
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(image: $image)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func addCompletion(photoURL: String? = nil) {
        isUploading = true
        errorMessage = nil
        
        // Optimistically update local state
        let newCompletion = Completion(goalId: goal.id!, date: date, status: .verified)
        goal.completions[ISO8601DateFormatter().string(from: date)] = newCompletion

        viewModel.addCompletion(for: goal, on: date, verificationPhotoUrl: photoURL)
        
        if goal.verificationMethod == .selfVerify {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.triggerRefund()
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let updatedGoal = self.viewModel.goals.first(where: { $0.id == self.goal.id }) {
                self.goal = updatedGoal
                self.onCompletion()
            }
            self.presentationMode.wrappedValue.dismiss()
        }
    }

    private func uploadPhotoAndAddCompletion() {
        guard let image = image, let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to prepare image for upload"
            return
        }

        isUploading = true
        errorMessage = nil

        let storageRef = Storage.storage().reference().child("goal_completions/\(goal.id ?? "")/\(date.timeIntervalSince1970).jpg")

        storageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                isUploading = false
                errorMessage = "Failed to upload image: \(error.localizedDescription)"
                return
            }

            storageRef.downloadURL { url, error in
                isUploading = false
                if let error = error {
                    errorMessage = "Failed to get download URL: \(error.localizedDescription)"
                    return
                }

                guard let downloadURL = url else {
                    errorMessage = "Failed to get download URL"
                    return
                }

                addCompletion(photoURL: downloadURL.absoluteString)
            }
        }
    }
    
    private func triggerRefund() {
        viewModel.triggerRefund(for: goal, on: date) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.completionStatus = .refunded
                case .failure(let error):
                    self.completionStatus = .refundFailed
                    self.errorMessage = "Refund failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func statusText(for status: Completion.CompletionStatus) -> String {
        switch status {
        case .pendingVerification:
            return "Pending Verification"
        case .verified:
            return "Verified"
        case .refunded:
            return "Refunded"
        case .refundFailed:
            return "Refund Failed"
        case .rejected:
            return "Rejected"
        case .missed:
            return "Missed"
        }
    }

    private func statusColor(for status: Completion.CompletionStatus) -> Color {
        switch status {
        case .pendingVerification:
            return .yellow
        case .verified, .refunded:
            return .green
        case .refundFailed, .rejected:
            return .red
        case .missed:
            return .orange
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }

            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
