import SwiftUI
import GoogleSignIn

enum AuthFlow {
    case signIn
    case signUp
}

struct GoogleSignInButtonView: View {
    @EnvironmentObject var userManager: UserManager
    var flow: AuthFlow = .signIn
    
    var body: some View {
        Button(action: {
            userManager.signInWithGoogle()
        }) {
            HStack {
                
                Image("google_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                
                Text("\(flow == .signIn ? "Sign in" : "Sign up") with Google")
                
            }
            .frame(maxWidth: .infinity, maxHeight: 50)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: 50)
        .background(Color.clear)
        .foregroundColor(.red)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.red, lineWidth: 1)
        )
    }
}
