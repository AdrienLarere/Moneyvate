import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @EnvironmentObject var subManager: SubscriptionManager

    var body: some View {
        List {
            // 1) If there's an error, show it
            if let error = subManager.errorMessage {
                Section {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                }
            }

            // 2) If the products are still empty & no error, it's likely loading
            if subManager.products.isEmpty && subManager.errorMessage == nil {
                Section {
                    Text("Loading subscription options…")
                }
            } else {
                // 3) Show each product
                ForEach(subManager.products, id: \.id) { product in
                    HStack {
                        Text(product.displayName)
                        Spacer()
                        Text(product.displayPrice)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            await subManager.purchase(product)
                        }
                    }
                }
            }

            // 4) Current Plan
            Section(header: Text("Current Plan")) {
                Text(subManager.currentPlanDescription)
            }
        }
        .navigationTitle("Subscription Options")
        .onAppear {
            Task {
                await subManager.fetchSubscriptions()
                await subManager.updateCurrentSubscription()
            }
        }
    }
}
