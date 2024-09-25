import Foundation
import Firebase
import FirebaseAuth
import FirebaseFirestore
import AuthenticationServices
import CryptoKit

class UserManager: NSObject, ObservableObject {
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var isEmailVerified = false
    @Published var isNewUser = false
    @Published var errorMessage: String?
    @Published var userProfile: UserProfile?
    
    var currentCurrency: String {
        return userProfile?.currency ?? "USD"
    }
    
    private var handle: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    private var appleSignInCompletion: ((Result<User, Error>) -> Void)?
    
    override init() {
        super.init()
        handle = Auth.auth().addStateDidChangeListener { [weak self] (auth, user) in
            self?.user = user
            self?.isAuthenticated = user != nil
            self?.isEmailVerified = user?.isEmailVerified ?? false
            if user != nil {
                self?.loadUserProfile()
            } else {
                self?.userProfile = nil
            }
        }
    }
    
    func isPasswordValid(_ password: String) -> Bool {
        let passwordRegex = "^(?=.*[A-Z])(?=.*\\d)(?=.*[@$!%*?&])[A-Za-z\\d@$!%*?&]{8,}$"
        return NSPredicate(format: "SELF MATCHES %@", passwordRegex).evaluate(with: password)
    }
        
    func signUp(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        guard isPasswordValid(password) else {
            self.errorMessage = "Password must be at least 8 characters long and contain at least one capital letter, one number, and one special character."
            completion(.failure(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: self.errorMessage!])))
            return
        }
        
        Auth.auth().createUser(withEmail: email, password: password) { [weak self] (result, error) in
            if let error = error as NSError? {
                if error.code == AuthErrorCode.emailAlreadyInUse.rawValue {
                    self?.errorMessage = "This email is already in use. Please try a different one."
                } else {
                    self?.errorMessage = error.localizedDescription
                }
                completion(.failure(error))
            } else if let user = result?.user {
                self?.isNewUser = true
                self?.sendVerificationEmail(user: user)
                completion(.success(user))
            }
        }
    }
    
    func signIn(email: String, password: String, completion: @escaping (Result<User, Error>) -> Void) {
        Auth.auth().signIn(withEmail: email, password: password) { (result, error) in
            if let error = error {
                completion(.failure(error))
            } else if let user = result?.user {
                if user.isEmailVerified {
                    completion(.success(user))
                } else {
                    self.sendVerificationEmail(user: user)
                    let error = NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Please verify your email address."])
                    completion(.failure(error))
                }
            }
        }
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            self.user = nil
            self.isAuthenticated = false
            self.isEmailVerified = false
            self.isNewUser = false
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
    
    private func sendVerificationEmail(user: User) {
        user.sendEmailVerification { error in
            if let error = error {
                print("Error sending verification email: \(error.localizedDescription)")
            } else {
                print("Verification email sent successfully")
            }
        }
    }
    
    func signInWithApple(completion: @escaping (Result<User, Error>) -> Void) {
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
        
        self.appleSignInCompletion = completion
    }
    
    private func signInWithApple(idTokenString: String, nonce: String, completion: @escaping (Result<User, Error>) -> Void) {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: nil
        )
        
        Auth.auth().signIn(with: credential) { (authResult, error) in
            if let error = error {
                completion(.failure(error))
            } else if let user = authResult?.user {
                completion(.success(user))
            }
        }
    }
    
    func loadUserProfile() {
        guard let user = Auth.auth().currentUser else { return }
        let db = Firestore.firestore()
        let docRef = db.collection("users").document(user.uid)
        
        docRef.getDocument { [weak self] (document, error) in
            if let document = document, document.exists {
                do {
                    self?.userProfile = try document.data(as: UserProfile.self)
                } catch {
                    print("Error decoding user profile: \(error)")
                }
            } else {
                // If the document does not exist, create a new user profile
                self?.createUserProfile(for: user)
            }
        }
    }

    func createUserProfile(for user: User) {
        let db = Firestore.firestore()
        let userProfile = UserProfile(id: user.uid, email: user.email ?? "", currency: "USD")
        do {
            try db.collection("users").document(user.uid).setData(from: userProfile)
            self.userProfile = userProfile
        } catch {
            print("Error creating user profile: \(error)")
        }
    }

    func updateUserProfile(currency: String) {
        guard let user = Auth.auth().currentUser else { return }
        let db = Firestore.firestore()
        db.collection("users").document(user.uid).updateData(["currency": currency]) { [weak self] error in
            if let error = error {
                print("Error updating user profile: \(error)")
            } else {
                self?.userProfile?.currency = currency
            }
        }
    }
    
    func checkEmailVerification(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        user.reload { [weak self] (error) in
            if let error = error {
                print("Error reloading user: \(error.localizedDescription)")
                completion(false)
            } else {
                self?.isEmailVerified = user.isEmailVerified
                completion(user.isEmailVerified)
            }
        }
    }
    
    func resendVerificationEmail(completion: @escaping (Bool) -> Void) {
        guard let user = Auth.auth().currentUser else {
            completion(false)
            return
        }
        
        user.sendEmailVerification { [weak self] error in
            if let error = error {
                self?.errorMessage = "Error resending verification email: \(error.localizedDescription)"
                completion(false)
            } else {
                self?.errorMessage = nil
                completion(true)
            }
        }
    }
    
    func randomNonceString(length: Int = 32) -> String {
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

    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

extension UserManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
            guard let nonce = currentNonce else {
                fatalError("Invalid state: A login callback was received, but no login request was sent.")
            }
            guard let appleIDToken = appleIDCredential.identityToken else {
                print("Unable to fetch identity token")
                return
            }
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                print("Unable to serialize token string from data: \(appleIDToken.debugDescription)")
                return
            }
            
            signInWithApple(idTokenString: idTokenString, nonce: nonce) { [weak self] result in
                self?.appleSignInCompletion?(result)
                self?.appleSignInCompletion = nil
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Sign in with Apple errored: \(error)")
        appleSignInCompletion?(.failure(error))
        appleSignInCompletion = nil
    }
}

extension UserManager: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windowScene = UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .compactMap { $0 as? UIWindowScene }
            .first
        
        return windowScene?.windows.first(where: { $0.isKeyWindow }) ?? UIWindow()
    }
}
