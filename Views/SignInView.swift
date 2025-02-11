import SwiftUI

struct SignInView: View {
    @EnvironmentObject var userManager: UserManager
    @State private var email = ""
    @State private var password = ""
    @Binding var isShowingSignUp: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            
            Text("Moneyvate Sign In")
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
            
            Button(action: signIn) {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            Spacer().frame(height: 10)
            
            GoogleSignInButtonView(flow: .signIn)
                .frame(height: 50)
                .environmentObject(userManager)
            
            AppleSignInButtonView(type: .signIn)
                .frame(height: 50)
                .environmentObject(userManager)
            
            Spacer().frame(height: 10)
            
            Button(action: { isShowingSignUp = true }) {
                Text("Don't have an account? Sign Up here")
                    .foregroundColor(.blue)
            }
        }
        .padding()
    }
    
    private func signIn() {
        userManager.signIn(email: email, password: password) { result in
            switch result {
            case .success:
                print("Signed in successfully")
            case .failure(let error):
                print("Sign in error: \(error.localizedDescription)")
            }
        }
    }
}
