import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var goalViewModel: GoalViewModel

    // Add a subscription manager
    @StateObject private var subManager = SubscriptionManager()

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var selectedCurrency = "USD"
    @State private var selectedTheme = "system"
    @State private var isDirty = false
    
    let currencies = ["USD", "GBP", "EUR"]
    let themeModes = ["system", "light", "dark"]

    var body: some View {
        Form {
            let email = userManager.userProfile?.email ?? "Unknown"
            // Account Info
            Section(header: Text("Account for \(email)")) {
                TextField("First Name", text: $firstName, onEditingChanged: { _ in isDirty = true })
                TextField("Last Name", text: $lastName, onEditingChanged: { _ in isDirty = true })
            }
            
            // Currency
            Section(header: Text("Currency")) {
                Picker("Select Currency", selection: $selectedCurrency) {
                    ForEach(currencies, id: \.self) { currency in
                        Text(currency)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedCurrency) { _, _ in
                    isDirty = true
                }
            }
            
            // Theme
            Section(header: Text("Theme")) {
                Picker("Appearance", selection: $selectedTheme) {
                    ForEach(themeModes, id: \.self) { mode in
                        Text(mode.capitalized)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .onChange(of: selectedTheme) { _, _ in
                    isDirty = true
                }
            }

            // Subscription status
            Section(header: Text("Subscription")) {
                Text("Current Plan: \(subManager.currentPlanDescription)")
                NavigationLink(destination: SubscriptionView()
                    .environmentObject(subManager)
                ) {
                    Text("Manage Subscription")
                }
            }

            // 2) Account deletion link
            Section {
                NavigationLink(destination: AccountDeletionModalView()
                    .environmentObject(goalViewModel)
                ) {
                    Text("Account Deletion Page")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            // Sync local fields from userProfile
            if let profile = userManager.userProfile {
                self.firstName = profile.firstName ?? ""
                self.lastName = profile.lastName ?? ""
                self.selectedCurrency = profile.currency
                self.selectedTheme = profile.themeMode ?? "system"
            }
            isDirty = false
        }
        // Save button
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isDirty {
                    Button("Save") {
                        userManager.updateUserProfile(
                            firstName: firstName,
                            lastName: lastName,
                            currency: selectedCurrency,
                            theme: selectedTheme
                        )
                        isDirty = false
                    }
                }
            }
        }
    }
}
