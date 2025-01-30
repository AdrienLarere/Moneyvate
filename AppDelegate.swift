import UIKit
import Firebase
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        FirebaseApp.configure()
        FirebaseConfiguration.shared.setLoggerLevel(.error)
        print("Firebase has been configured")
        print("Firebase configured. Project ID:", FirebaseApp.app()?.options.projectID ?? "nil")
        print("Storage bucket:", FirebaseApp.app()?.options.storageBucket ?? "nil")
        return true
    }
}
