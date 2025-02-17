import SwiftUI
import FirebaseAuth

struct EmailVerificationView: View {
    @EnvironmentObject var userManager: UserManager
    @State private var isChecking = false
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var resendCooldown = 0
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Please verify your account")
                .font(.headline)
            
            Text("A verification link has been sent to your email address. Please click on the link to verify your account.")
                .multilineTextAlignment(.center)
                .padding()
            
            Button(action: checkVerification) {
                Text("I've verified my email")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isChecking)
            
            Button(action: resendEmail) {
                Text(resendCooldown > 0 ? "Resend Email (\(resendCooldown)s)" : "Resend Email")
                    .padding()
                    .background(resendCooldown > 0 ? Color.gray : Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(isChecking || resendCooldown > 0)
            
            if isChecking {
                ProgressView()
            }
            
            Spacer()
            
            HStack {
                Button(action: backToHomepage) {
                    Text("Back to homepage")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                Spacer()
            }
        }
        .padding()
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Notification"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .onReceive(timer) { _ in
            if resendCooldown > 0 {
                resendCooldown -= 1
            }
        }
    }
    
    private func checkVerification() {
        isChecking = true
        Auth.auth().currentUser?.reload { error in
            isChecking = false
            if let error = error {
                alertMessage = "Error reloading user: \(error.localizedDescription)"
                showingAlert = true
            } else {
                let isVerified = Auth.auth().currentUser?.isEmailVerified ?? false
                if isVerified {
                    // 1) If verified, either navigate to main or sign them out
                    // For example, sign out so they can sign in again:
                    userManager.signOut()

                    // Then maybe present a success alert
                    alertMessage = "Email is verified! Please sign in again."
                    showingAlert = true

                    // Or if you have a main app flow, do a custom navigate:
                    // e.g. isVerifiedFlow = true
                } else {
                    alertMessage = "Email is not yet verified. Please check your inbox/spam."
                    showingAlert = true
                }
            }
        }
    }
    
    
    private func resendEmail() {
        isChecking = true
        userManager.resendVerificationEmail { success in
            isChecking = false
            if success {
                alertMessage = "Verification email has been resent. Please check your inbox and spam folder."
                resendCooldown = 60  // Start a 60-second cooldown
            } else {
                alertMessage = userManager.errorMessage ?? "Failed to resend verification email. Please try again later."
            }
            showingAlert = true
        }
    }
    
    private func backToHomepage() {
        userManager.signOut()
    }
}
