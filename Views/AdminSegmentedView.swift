import SwiftUI

struct AdminSegmentedView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        VStack {
            Picker("Section", selection: $selectedTab) {
                Text("Goals").tag(0)
                Text("Admin").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()

            // Show whichever tab is selected
            if selectedTab == 0 {
                GoalsView()
            } else {
                AdminView()
            }
        }
        .edgesIgnoringSafeArea(.bottom)
    }
}
