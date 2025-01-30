import SwiftUI
import FirebaseStorage
import FirebaseFirestore
import Foundation
import FirebaseStorage
import FirebaseAuth

struct CompletionModalView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: GoalViewModel
    @Binding var goal: Goal
    let dayString: String
    @State private var image: UIImage?
    @State private var isShowingImagePicker = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var completionStatus: Completion.CompletionStatus?
    @State private var explanation: String = ""
    @State private var adminApprovalToggle = false
    
    var onCompletion: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 10)
            
            Text(goal.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text(displayDateString(for: dayString))
                .font(.subheadline)
                .italic()
                .foregroundColor(.secondary)
            
            Spacer().frame(height: 20)

            // If it's photoVerification => show the new UI
            if goal.verificationMethod == .photoVerification {
                
                if let image = image {
                    // The image area: we fix a height so it doesn't push the button down
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        // For example, a 180 height
                        .frame(height: 180)
                        .clipped()
                } else {
                    // If no image, we can show a placeholder or just an empty space
                    // with the same height so it doesn't push the button down when image appears
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 180)
                }
                
                
                // "Upload Photo" button in white, with blue text/border
                Button(action: {
                    isShowingImagePicker = true
                }) {
                    Text(image == nil ? "Upload Photo" : "Change Photo")
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                }
                .background(Color.white)
                .cornerRadius(10)
                
                // Optional text field for explanation
                TextField("Optional comment", text: $explanation)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.8), lineWidth: 1) // Darker gray border
                    )
                    .padding(.top, 8)
                
                // A checkbox toggle
                Toggle(isOn: $adminApprovalToggle) {
                    Text("I understand the admin will decide whether to approve or decline this completion based on my picture.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .toggleStyle(ResponsibilityCheckboxToggleStyle())
                .padding(.top, 4)
                
                // Helper text
                Text("Your photos are automatically deleted from our servers after 7 days")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)  // Space before button

                // Now the "Submit" button (blue background, white text)
                if image != nil {
                    Button("Submit") {
                        uploadPhotoAndAddCompletion()
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(adminApprovalToggle ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(!adminApprovalToggle || isUploading)
                }
                
            } else {
                // The selfVerify approach:
                Text("I swear on my honor that I have achieved my goal and deserve my money back.")
                    .font(.body)
                    .padding(.bottom, 5)
                    .multilineTextAlignment(.center)
                
                Button("I swear") {
                    confirmCompletion()
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(isUploading)
            }

            if let status = completionStatus {
                Text(statusText(for: status))
                    .foregroundColor(statusColor(for: status))
                    .padding(.top, 10)
            }

            if isUploading {
                ProgressView("Uploading...")
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding(.top, 4)
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

    private func confirmCompletion(photoURL: String? = nil) {
        isUploading = true
        errorMessage = nil
        
        print("=== Confirm tapped ===")
        print("Goal ID: \(goal.id ?? "nil")")
        print("dayString: \(dayString)")

        // 1) Call a new function in your GoalViewModel that queries by dayString
        viewModel.verifyCompletion(for: goal, dayString: dayString, verificationPhotoUrl: photoURL)
        
        // 2) If selfVerify, do refund
        if goal.verificationMethod == .selfVerify {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.triggerRefund()
            }
        }
        
        // 3) Dismiss the modal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let updatedGoal = self.viewModel.goals.first(where: { $0.id == self.goal.id }) {
                self.goal = updatedGoal
                self.onCompletion()
            }
            self.presentationMode.wrappedValue.dismiss()
        }
    }


    private func uploadPhotoAndAddCompletion() {
        // 1) Check auth
        guard let user = Auth.auth().currentUser else {
            print("❌ No user is signed in. Storage rules require auth!")
            errorMessage = "No user authenticated."
            return
        }
        let userId = user.uid
        
        // 2) Check image
        guard let image = image, let imageData = image.jpegData(compressionQuality: 0.8) else {
            errorMessage = "Failed to prepare image for upload"
            return
        }
        
        isUploading = true
        errorMessage = nil
        
        // 3) Build the path with userId + goalId
        let finalPath = "GoalCompletions/User-\(userId)/Goal-\(goal.id ?? "UnknownGoal")/\(dayString)-\(UUID().uuidString).jpg"
        
        print("Final path is:", finalPath)
        
        let storageRef = Storage.storage().reference().child(finalPath)
        
        // 4) Put the data
        storageRef.putData(imageData, metadata: nil) { metadata, error in
            if let error = error {
                self.isUploading = false
                let nsError = error as NSError
                self.errorMessage = "Failed to upload image: \(error.localizedDescription)"
                print("Full error domain/code:", nsError.domain, nsError.code)
                print("Error from putData:", error.localizedDescription)
                return
            }
            
            // 5) Get download URL
            storageRef.downloadURL { url, error in
                self.isUploading = false
                if let error = error {
                    self.errorMessage = "Failed to get download URL: \(error.localizedDescription)"
                    return
                }
                
                guard let downloadURL = url else {
                    self.errorMessage = "Failed to get download URL"
                    return
                }
                
                let photoURL = downloadURL.absoluteString
                print("Uploaded photo URL: \(photoURL), Explanation: \(self.explanation)")
                
                // 6) Mark completion as pending verification
                self.viewModel.verifyCompletion(
                    for: self.goal,
                    dayString: self.dayString,
                    verificationPhotoUrl: photoURL,
                    explanation: self.explanation
                )
                
                // 7) Dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let updatedGoal = self.viewModel.goals.first(where: { $0.id == self.goal.id }) {
                        self.goal = updatedGoal
                        self.onCompletion()
                    }
                    self.presentationMode.wrappedValue.dismiss()
                }
            }
        }
    }

    
    private func triggerRefund() {
        viewModel.triggerRefund(for: goal, dayString: dayString) { result in
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
        case .nonSubmitted:
            return "Not Submitted"
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
        case .nonSubmitted, .pendingVerification:
            return .gray
        case .verified, .refunded:
            return .green
        case .refundFailed, .rejected:
            return .red
        case .missed:
            return .orange
        }
    }
    
    private func displayDateString(for dayString: String) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        if let localDate = df.date(from: dayString) {
            let prettyFormatter = DateFormatter()
            prettyFormatter.dateStyle = .medium
            return prettyFormatter.string(from: localDate)
        }
        return dayString  // fallback
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

struct ResponsibilityCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            Image(systemName: configuration.isOn ? "checkmark.square" : "square")
                .foregroundColor(configuration.isOn ? .blue : .gray)
                .onTapGesture {
                    configuration.isOn.toggle()
                }
            configuration.label
        }
    }
}
