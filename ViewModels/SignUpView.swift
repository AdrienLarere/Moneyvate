import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @EnvironmentObject var userManager: UserManager
    @State private var email = ""
    @State private var password = ""
    @Environment(\.presentationMode) var presentationMode
    @State private var showingAlert = false
    @State private var showingErrorAlert = false
    @State private var alertMessage = ""
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Sign Up")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            TextField("Email", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Button(action: signUp) {
                Text("Sign Up")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            
//            SignInWithAppleButton(type: .signUp)
//                .frame(height: 50)
//                .onTapGesture(perform: signUpWithApple)
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
                presentationMode.wrappedValue.dismiss()
            case .failure(let error):
                errorMessage = userManager.errorMessage ?? error.localizedDescription
                showingErrorAlert = true
            }
        }
    }
    
//    private func signUpWithApple() {
//        let nonce = userManager.randomNonceString()
//        let appleIDProvider = ASAuthorizationAppleIDProvider()
//        let request = appleIDProvider.createRequest()
//        request.requestedScopes = [.fullName, .email]
//        request.nonce = userManager.sha256(nonce)
//
//        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
//        authorizationController.delegate = userManager
//        authorizationController.presentationContextProvider = userManager
//        authorizationController.performRequests()
//
//        // The actual sign in will be handled in the UserManager's authorizationController delegate method
//    }
}
