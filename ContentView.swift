import SwiftUI
import FirebaseAuth
import FirebaseStorage

struct ContentView: View {
    @EnvironmentObject var viewModel: GoalViewModel
    @EnvironmentObject var userManager: UserManager
    @State private var isShowingSignUp = false
    
    var body: some View {
        Group {
            // 1) Are we authenticated?
            if userManager.isAuthenticated {
                // 2) Is their email verified?
                if userManager.isEmailVerified {
                    // 3) Show admin or normal goals
                    mainView
                } else {
                    EmailVerificationView()
                }
            } else {
                // 4) If not authenticated
                if userManager.isNewUser {
                    EmailVerificationView()
                } else {
                    signInView
                }
            }
        }
        .onChange(of: userManager.isAuthenticated) { oldValue, newValue in
            if newValue {
                DispatchQueue.main.async {
                    self.viewModel.fetchGoals()
                }
            } else {
                DispatchQueue.main.async {
                    self.viewModel.clearGoals()
                }
            }
        }
    }
    
    private var signInView: some View {
        SignInView(isShowingSignUp: $isShowingSignUp)
            .sheet(isPresented: $isShowingSignUp) {
                SignUpView()
            }
    }
    
    // The only logic: if admin => AdminSegmentedView, else => GoalsView
    private var mainView: some View {
        Group {
            if userManager.userProfile?.isAdmin == true {
                // Show the Admin layout
                AdminSegmentedView()
                    .environmentObject(viewModel)
                    .environmentObject(userManager)
            } else {
                // Show the normal goals layout
                GoalsView()
                    .environmentObject(viewModel)
                    .environmentObject(userManager)
            }
        }
    }
}
