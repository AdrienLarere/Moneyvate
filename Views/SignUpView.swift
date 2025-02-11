import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @EnvironmentObject var userManager: UserManager
    @State private var email = ""
    @State private var password = ""
    @Environment(\.dismiss) private var dismiss
    @State private var showingAlert = false
    @State private var showingErrorAlert = false
    @State private var alertMessage = ""
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Moneyvate Sign Up")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Spacer().frame(height: 10)
            
            // Email Field with custom border
            TextField("Email", text: $email)
                .padding(10)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary, lineWidth: 0.5)
                )
                .autocapitalization(.none)
            
            // Password Field with custom border
            SecureField("Password", text: $password)
                .padding(10)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary, lineWidth: 0.5)
                )
            
            Button(action: signUp) {
                Text("Sign Up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Spacer().frame(height: 10)
            
            GoogleSignInButtonView(flow: .signUp)
                .frame(height: 50)
                .environmentObject(userManager)
            
            AppleSignInButtonView(type: .signUp)
                .frame(height: 50)
                .environmentObject(userManager)
        }
        .padding()
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Sign Up"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
    }
    
    private func signUp() {
        userManager.signUp(email: email, password: password) { result in
            switch result {
            case .success:
                print("Signed up successfully")
                dismiss()
            case .failure(let error):
                errorMessage = userManager.errorMessage ?? error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
}
