import Foundation

enum Env {
    case development
    case production
}

struct AppConfig {
    static let environment: Env = {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }()
    
    static let serverURL: String = {
        switch environment {
        case .development:
            return "https://moneyvate-server-dev-f596ca194fd7.herokuapp.com"
        case .production:
            return "https://moneyvate-server-prod-75e2b98a163b.herokuapp.com"
        }
    }()
    
    static let stripePublishableKey: String = {
        switch environment {
        case .development:
            return "pk_test_51PwlZSGdTaD2941MrqMJFdRpIoa55zd753w9rdvz2vZG03mvDMJFvrpI5NYY9dVnkPeY5mnhaTTZkhZxhGjyQqO500t1postuQ"
        case .production:
            return "pk_live_51PwlZSGdTaD2941MpwtZ4ICGH8bYp8MObRV3zMDqHSO2xr6MURYQaaso9B9dMe2sDIRof86iLgM5fPVpJbb52WjH00RdtHNZdv"
        }
    }()
    
    // Add any other configuration variables here
}
