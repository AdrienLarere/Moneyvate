import SwiftUI
import Firebase

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
        }
    }
}
