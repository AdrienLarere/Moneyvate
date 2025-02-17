import SwiftUI
import FirebaseAuth

struct AccountDeletionModalView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var goalViewModel: GoalViewModel // same instance from environment

    @State private var isProcessing = false
    @State private var alertMessage = ""
    @State private var showConfirmationAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Account Deletion")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("""
                Deleting your account is easy.\n\n If you do we will refund all remaining funds for any of your current & future goals, and delete your account. \n\n All of your goals will be deleted. \n\n*To avoid users abusing account deletion to escape their goals, we are adding a light penalty: You will not be able to create a new account for **2 weeks***.
                """)
                .multilineTextAlignment(.center)
                .padding()
                
                if isProcessing {
                    ProgressView("Processing...")
                }
                
                Button {
                    print("Delete account button tapped.")
                    showConfirmationAlert = true
                } label: {
                    Text("Delete account")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red, lineWidth: 2)
                        )
                }
                .foregroundColor(.red)
                .disabled(isProcessing)
                
                Spacer()
            }
            .padding()
            .navigationBarBackButtonHidden(false)
            // The two-button confirm
            .alert("Confirm Deletion", isPresented: $showConfirmationAlert) {
                Button("Yes, delete", role: .destructive) {
                    print("User confirmed deletion.")
                    deleteAccountFlow()
                }
                Button("Cancel", role: .cancel) {
                    print("User canceled deletion.")
                }
            } message: {
                Text("Are you sure you want to permanently delete your account?")
            }
            // The final result alert
            .alert("Account Deletion", isPresented: Binding<Bool>(
                get: { !alertMessage.isEmpty },
                set: { _ in alertMessage = "" }
            )) {
                Button("OK") {
                    if alertMessage.contains("successfully") {
                        dismiss()
                    }
                }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func deleteAccountFlow() {
        isProcessing = true
        alertMessage = ""
        print("Starting deleteAccountFlow (refund+delete)")

        // 0) Capture the user info while they're still signed in
        guard let user = Auth.auth().currentUser,
              let userEmail = user.email else {
            self.alertMessage = "No current user or missing email. Cannot delete."
            self.isProcessing = false
            return
        }
        let userUID = user.uid

        // 1) Refund + delete active goals
        goalViewModel.refundAndDeleteAllActiveGoals { refundResult in
            print("refundAndDeleteAllActiveGoals result: \(refundResult)")
            switch refundResult {
            case .success:
                // 2) Remove the Firestore user doc
                print("Goals refunded/deleted. Now removing Firestore user doc for uid=\(userUID)")
                userManager.deleteUserFirestoreDoc(uid: userUID) { docResult in
                    switch docResult {
                    case .success:
                        print("Firestore user doc removed. Now record deletion in userInfo.")
                        // 3) recordAccountDeletion(forEmail:)
                        userManager.recordAccountDeletion(forEmail: userEmail) { recordResult in
                            switch recordResult {
                            case .success:
                                print("Recorded deletion in userInfo/\(userEmail). Now remove user from Auth.")
                                // 4) Finally, remove from Firebase Auth
                                userManager.deleteUserAccount { deleteResult in
                                    DispatchQueue.main.async {
                                        self.isProcessing = false
                                        switch deleteResult {
                                        case .success:
                                            // success
                                            self.alertMessage = "Account fully deleted. You cannot create a new account for 2 weeks."
                                            print("Firebase Auth user deleted. Flow complete.")
                                        case .failure(let error):
                                            // Possibly re-check if it's requiresRecentLogin
                                            if let nsErr = error as NSError?, nsErr.code == AuthErrorCode.requiresRecentLogin.rawValue {
                                                self.alertMessage = """
                                                We need a recent login before final deletion.
                                                Please sign out, sign back in, and try again.
                                                """
                                                print("User must re-auth to finalize deletion from Auth.")
                                            } else {
                                                self.alertMessage = "Failed to remove from Auth: \(error.localizedDescription)"
                                                print("Error removing from Auth: \(error.localizedDescription)")
                                            }
                                        }
                                    }
                                }
                                
                            case .failure(let error):
                                DispatchQueue.main.async {
                                    self.isProcessing = false
                                    self.alertMessage = "Removed user doc, but failed to record deletion: \(error.localizedDescription)"
                                    print("Error recordAccountDeletion(forEmail:): \(error.localizedDescription)")
                                }
                            }
                        }
                        
                    case .failure(let err):
                        DispatchQueue.main.async {
                            self.isProcessing = false
                            self.alertMessage = "Failed to remove Firestore doc: \(err.localizedDescription)"
                            print("Error deleting user doc: \(err.localizedDescription)")
                        }
                    }
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self.isProcessing = false
                    self.alertMessage = "Refund & delete of goals failed: \(error.localizedDescription)"
                    print("Refund & delete error: \(error.localizedDescription)")
                }
            }
        }
    }

}
