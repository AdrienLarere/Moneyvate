import SwiftUI
import FirebaseFirestore

import SwiftUI
import FirebaseFirestore

struct AdminView: View {
    @StateObject private var viewModel = AdminViewModel()
    @State private var selectedCompletionRef: IdentifiableReference?
    
    var body: some View {
        NavigationView {
            List {
                // Only show the "Verification Requests" section if there are pending completions.
                if !viewModel.pendingCompletions.isEmpty {
                    Section(header: Text("Verification Requests")) {
                        ForEach(viewModel.pendingCompletions, id: \.ref.documentID) { item in
                            Button {
                                // Tapping opens the AdminPhotoVerificationView
                                selectedCompletionRef = IdentifiableReference(item.ref)
                            } label: {
                                CompletionRow(completion: item.completion)
                            }
                        }
                    }
                }
                
                // Only show the "Rejected Requests" section if there are rejected completions.
                if !viewModel.rejectedCompletions.isEmpty {
                    Section(header: Text("Rejected Requests")) {
                        ForEach(viewModel.rejectedCompletions, id: \.ref.documentID) { item in
                            HStack {
                                CompletionRow(completion: item.completion)
                                Spacer()
                                Button("Undo") {
                                    viewModel.undoRejection(item.ref)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                // Only show the "Verified Requests" section if there are verified (or refunded) completions.
                if !viewModel.verifiedPhotoCompletions.isEmpty {
                    Section(header: Text("Verified Requests")) {
                        ForEach(viewModel.verifiedPhotoCompletions, id: \.ref.documentID) { item in
                            // Simply display the completion row (which now shows a loader if status is verified)
                            CompletionRow(completion: item.completion)
                        }
                    }
                }
            }
            .sheet(item: $selectedCompletionRef) { wrapper in
                AdminPhotoVerificationView(ref: wrapper.ref, viewModel: viewModel)
            }
            .navigationTitle("Admin")
        }
    }
}


struct CompletionRow: View {
    let completion: Completion
    
    var body: some View {
        HStack {
            // 1) Image or fallback
            if let urlString = completion.verificationPhotoUrl,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .cornerRadius(8)
                    
                    case .empty:
                       ProgressView().frame(width: 50, height: 50)
                        
                    case .failure(_):
                       fallbackBox
                        
                    @unknown default:
                        fallbackBox
                    }
                }
            } else {
                // If no URL at all, show the fallback box
                fallbackBox
            }
            
            // 2) Main text: date + optional explanation
            VStack(alignment: .leading) {
                Text(completion.date, style: .date)
                if let explanation = completion.explanation {
                    Text(explanation)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding(.leading, 8)
            
            // 3) Spacer, then show status if verified/refunded
            Spacer()
            
            if completion.status == .verified {
                HStack(spacing: 8) {
                    Text("Verified")
                        .foregroundColor(.green)
                        .font(.callout)
                    CustomLoader(
                        size: 12,
                        lineWidth: 1,
                        color: .green,
                        rotationDuration: 3
                    )
                }
            } else if completion.status == .refunded {
                Text("Refunded")
                    .foregroundColor(.green)
                    .font(.callout)
            }
        }
    }
    
    // A small white square with gray border, rounded edges
    private var fallbackBox: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.gray, lineWidth: 1)
            .background(Color.white)
            .frame(width: 50, height: 50)
    }
}

struct IdentifiableReference: Identifiable {
    let id: String
    let ref: DocumentReference
    
    init(_ ref: DocumentReference) {
        self.id = ref.documentID
        self.ref = ref
    }
}
