import StoreKit
import SwiftUI

@MainActor
class SubscriptionManager: ObservableObject {
    private let productIDs = [
        "com.moneyvate.sub.weekly",   // Example
        "com.moneyvate.sub.monthly",
        "com.moneyvate.sub.yearly"
    ]

    @Published var products: [Product] = []
    @Published var currentSubscriptionID: String?
    @Published var errorMessage: String?

    init() {
        Task {
            await fetchSubscriptions()
            await updateCurrentSubscription()
        }
    }

    func fetchSubscriptions() async {
        // Clear errors each time
        self.errorMessage = nil
        do {
            let storeProducts = try await Product.products(for: productIDs)
            if storeProducts.isEmpty {
                self.errorMessage = "No products found in App Store. Check your product IDs."
            }
            self.products = storeProducts.sorted(by: { $0.displayPrice < $1.displayPrice })
        } catch {
            self.errorMessage = "Error fetching products: \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async {
        self.errorMessage = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                currentSubscriptionID = transaction.productID
                await transaction.finish()
            case .userCancelled:
                print("User cancelled purchase.")
            case .pending:
                print("Purchase pending.")
            default:
                print("Unhandled result: \(result)")
            }
        } catch {
            self.errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func updateCurrentSubscription() async {
        self.errorMessage = nil
        // Check entitlements
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if productIDs.contains(transaction.productID) {
                currentSubscriptionID = transaction.productID
                return
            }
        }
        // If none found
        currentSubscriptionID = nil
    }

    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw NSError(domain: "SubscriptionManager",
                          code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Unverified transaction"])
        }
    }

    /// If no plan => "Free"
    var currentPlanDescription: String {
        guard let subID = currentSubscriptionID else {
            return "Free"
        }
        switch subID {
        case "com.moneyvate.sub.weekly":
            return "Weekly Plan"
        case "com.moneyvate.sub.monthly":
            return "Monthly Plan"
        case "com.moneyvate.sub.yearly":
            return "Yearly Plan"
        default:
            return "Unknown Plan"
        }
    }

    /// True if user is subscribed to any plan
    var isSubscribed: Bool {
        return currentSubscriptionID != nil
    }
}
