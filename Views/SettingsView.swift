import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var userManager: UserManager
    @State private var selectedCurrency = "USD"
    let currencies = ["USD", "GBP", "EUR"]
    
    var body: some View {
        Form {
            Section(header: Text("Account")) {
                if let email = userManager.userProfile?.email {
                    Text("You are logged in as: \(email)")
                } else {
                    Text("No email available")
                }
            }
            
            Section(header: Text("Currency")) {
                Picker("Select Currency", selection: $selectedCurrency) {
                    ForEach(currencies, id: \.self) { currency in
                        Text(currency)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedCurrency) { oldCurrency, newCurrency in
                    userManager.updateUserProfile(currency: newCurrency)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            selectedCurrency = userManager.userProfile?.currency ?? "USD"
        }
    }
}
