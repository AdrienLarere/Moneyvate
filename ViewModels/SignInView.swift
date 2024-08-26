import SwiftUI

struct SignInView: View {
    @EnvironmentObject var userManager: UserManager
    @State private var email = ""
    @State private var password = ""
    @Binding var isShowingSignUp: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Sign In")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: signIn) {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
            SignInWithAppleButton(type: .signIn)
                .frame(height: 50)
            
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
