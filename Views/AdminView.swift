import SwiftUI

struct AdminView: View {
    var body: some View {
        NavigationView {
            VStack {
                Text("Admin Panel")
                    .font(.largeTitle)
                Text("Manage photo submissions, user approvals, etc. here.")
                    .foregroundColor(.gray)
                    .padding(.top)
            }
        }
    }
}
