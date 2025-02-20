import SwiftUI
import Firebase
import FirebaseCore
import FirebaseStorage

@main
struct MoneyvateApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var goalViewModel = GoalViewModel()
    @StateObject private var userManager = UserManager()
    @StateObject private var subManager = SubscriptionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(goalViewModel)
                .environmentObject(userManager)
                .environmentObject(subManager)
        }
    }
}
