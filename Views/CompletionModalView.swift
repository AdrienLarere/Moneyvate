import SwiftUI
import FirebaseStorage
import FirebaseFirestore

struct CompletionModalView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: GoalViewModel
    let goal: Goal
    let date: Date
    @State private var image: UIImage?
    @State private var isShowingImagePicker = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Complete Goal")
                .font(.headline)
            
            if goal.verificationMethod == .selfVerify {
                Text("I confirm that I have successfully completed my task today")
                    .multilineTextAlignment(.center)
                
                Button("Confirm") {
                    addCompletion()
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            } else {
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
            
            if isUploading {
                ProgressView()
            }
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }
        }
        .padding()
        .sheet(isPresented: $isShowingImagePicker) {
            ImagePicker(image: $image)
        }
    }
    
    private func addCompletion(photoURL: String? = nil) {
        let newCompletion = Completion(
            goalId: goal.id ?? "",
            date: date,
            status: goal.verificationMethod == .selfVerify ? .verified : .pendingVerification,
            verificationPhotoUrl: photoURL
        )
        
        viewModel.addCompletion(for: goal, on: date)
        presentationMode.wrappedValue.dismiss()
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
