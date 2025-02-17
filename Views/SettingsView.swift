import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var goalViewModel: GoalViewModel

    // Local copies for editing
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var selectedCurrency = "USD"

    // Track whether user changed anything
    @State private var isDirty = false

    let currencies = ["USD", "GBP", "EUR"]
    
    var body: some View {
        Form {
            let email = userManager.userProfile?.email ?? "Unknown"
            Section(header: Text("Account for \(email)")) {
                TextField("First Name", text: $firstName, onEditingChanged: { _ in
                    isDirty = true
                })
                TextField("Last Name", text: $lastName, onEditingChanged: { _ in
                    isDirty = true
                })
            }
            
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
            }
            // Set isDirty to false
            isDirty = false
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isDirty {
                    Button("Save") {
                        userManager.updateUserProfile(
                            firstName: firstName,
                            lastName: lastName,
                            currency: selectedCurrency
                        )
                        isDirty = false
                    }
                }
            }
        }
    }
}
