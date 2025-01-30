import SwiftUI
import Firebase
import FirebaseCore
import FirebaseStorage

@main
struct MoneyvateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var goalViewModel = GoalViewModel()
    @StateObject private var userManager = UserManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(goalViewModel)
                .environmentObject(userManager)
                .onAppear {
                    // Or do it here
                    let defaultBucket = Storage.storage().reference().bucket
                    print("Default bucket is:", defaultBucket)
                }
        }
    }
}
