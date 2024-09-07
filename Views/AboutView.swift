import SwiftUI
import MessageUI

struct AboutView: View {
    @State private var isShowingMailView = false
    @State private var mailResult: Result<MFMailComposeResult, Error>? = nil
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Moneyvate")
                    .font(.title)
                
                Text("Moneyvate is an app designed to help you achieve your goals through financial motivation. \nSet goals, commit funds, and earn them back as you make progress.")
                
                Text("Created by: Adrien Larere")
                
                Divider()
                
                Text("Contact Us")
                    .font(.title2)
                
                Button("Send Email") {
                    isShowingMailView.toggle()
                }
                .disabled(!MFMailComposeViewController.canSendMail())
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("About & Contact")
        .sheet(isPresented: $isShowingMailView) {
            EmailSender(result: $mailResult)
        }
        .alert(isPresented: $showingAlert) {
            Alert(title: Text("Email Result"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .onChange(of: isShowingMailView) { _, newValue in
            if newValue == false {
                handleMailResult()
            }
        }
    }
    
    private func handleMailResult() {
        guard let result = mailResult else { return }
        
        switch result {
        case .success(let sendResult):
            switch sendResult {
            case .sent:
                alertMessage = "Email sent successfully."
            case .saved:
                alertMessage = "Email saved as draft."
            case .cancelled:
                alertMessage = "Email cancelled."
            case .failed:
                alertMessage = "Email failed to send."
            @unknown default:
                alertMessage = "Unknown email result."
            }
        case .failure(let error):
            alertMessage = "Failed to send email: \(error.localizedDescription)"
        }
        
        showingAlert = true
    }
}

struct EmailSender: UIViewControllerRepresentable {
    @Binding var result: Result<MFMailComposeResult, Error>?
    @Environment(\.presentationMode) var presentationMode
    
    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        @Binding var result: Result<MFMailComposeResult, Error>?
        let parent: EmailSender
        
        init(result: Binding<Result<MFMailComposeResult, Error>?>, parent: EmailSender) {
            _result = result
            self.parent = parent
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            if let error = error {
                self.result = .failure(error)
            } else {
                self.result = .success(result)
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(result: $result, parent: self)
    }
    
    func makeUIViewController(context: UIViewControllerRepresentableContext<EmailSender>) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients(["adrien.larere@gmail.com"])
        vc.setSubject("Moneyvate App Inquiry")
        vc.setMessageBody("Hello, I have a question about the Moneyvate app.", isHTML: false)
        return vc
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController,
                                context: UIViewControllerRepresentableContext<EmailSender>) {
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AboutView()
        }
    }
}
