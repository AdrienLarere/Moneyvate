import SwiftUI
import AuthenticationServices
import CryptoKit

struct AppleSignInButtonView: UIViewRepresentable {
    @EnvironmentObject var userManager: UserManager
    var type: ASAuthorizationAppleIDButton.ButtonType
    
    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: type, style: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.startSignInWithAppleFlow), for: .touchUpInside)
        return button
    }
    
    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }
    
    class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let parent: AppleSignInButtonView
        private var currentNonce: String?
        
        init(_ parent: AppleSignInButtonView) {
            self.parent = parent
        }
        
        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            let windowScene = UIApplication.shared.connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .compactMap { $0 as? UIWindowScene }
                .first
            
            let window = windowScene?.windows
                .first(where: { $0.isKeyWindow }) ?? UIWindow()
            
            return window
        }
        
        // In your Coordinator:
        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            guard
              let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce,    // We stored it in startSignInWithAppleFlow
              let _ = appleIDCredential.identityToken
            else {
                print("Unable to get AppleIDCredential or nonce.")
                return
            }

            // Actually call userManager
            parent.userManager.signInWithApple(credential: appleIDCredential,
                                               nonce: nonce) { result in
                switch result {
                case .success(let user):
                    print("Signed in with Apple successfully: \(user.uid)")
                case .failure(let error):
                    print("Error signing in with Apple: \(error.localizedDescription)")
                }
            }
        }

        
        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            let nsError = error as NSError
            print("Sign in with Apple errored: \(nsError), code=\(nsError.code), desc=\(nsError.localizedDescription)")
        }
        
        @objc func startSignInWithAppleFlow() {
            let nonce = randomNonceString()
            currentNonce = nonce
            let appleIDProvider = ASAuthorizationAppleIDProvider()
            let request = appleIDProvider.createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
            
            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = self
            authorizationController.presentationContextProvider = self
            authorizationController.performRequests()
        }
        
        private func randomNonceString(length: Int = 32) -> String {
            precondition(length > 0)
            let charset: [Character] =
                Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
            var result = ""
            var remainingLength = length
            
            while remainingLength > 0 {
                let randoms: [UInt8] = (0 ..< 16).map { _ in
                    var random: UInt8 = 0
                    let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                    if errorCode != errSecSuccess {
                        fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                    }
                    return random
                }
                
                randoms.forEach { random in
                    if remainingLength == 0 {
                        return
                    }
                    
                    if random < charset.count {
                        result.append(charset[Int(random)])
                        remainingLength -= 1
                    }
                }
            }
            
            return result
        }
        
        private func sha256(_ input: String) -> String {
            let inputData = Data(input.utf8)
            let hashedData = SHA256.hash(data: inputData)
            let hashString = hashedData.compactMap {
                String(format: "%02x", $0)
            }.joined()
            
            return hashString
        }
    }
}
