import SwiftUI
import FirebaseFirestore

struct AdminUsersView: View {
    @EnvironmentObject var userManager: UserManager
    @State private var users: [UserProfile] = []
    
    var body: some View {
        List(users, id: \.id) { user in
            NavigationLink(destination: AdminUserGoalsView(user: user)) {
                Text(user.email)
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Select a User")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchAllUsers()
        }
    }
    
    private func fetchAllUsers() {
        let db = Firestore.firestore()
        db.collection("users").getDocuments { snapshot, error in
            if let error = error {
                print("Error fetching users: \(error.localizedDescription)")
                return
            }
            if let docs = snapshot?.documents {
                self.users = docs.compactMap { try? $0.data(as: UserProfile.self) }
            }
        }
    }
}
