import SwiftUI
import StripePaymentSheet

struct PaymentSheetUI: UIViewControllerRepresentable {
    let paymentSheet: PaymentSheet
    let onCompletion: (PaymentSheetResult) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if uiViewController.view.window != nil {
                self.paymentSheet.present(from: uiViewController) { result in
                    self.onCompletion(result)
                }
            } else {
                print("View controller is not in window hierarchy")
            }
        }
    }
}
