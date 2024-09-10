import SwiftUI
import UIKit
import Stripe
import StripePaymentSheet
import Combine
import Network

class PaymentViewModel: ObservableObject {
    @Published var paymentSheet: PaymentSheet?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isNetworkAvailable = true
    private let monitor = NWPathMonitor()

    init() {
        startNetworkMonitoring()
        fetchEnvironment()
    }

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }

    func createPaymentIntent(amount: Int, completion: @escaping (Bool) -> Void) {
        print("Creating payment intent for amount: \(amount)")
        isLoading = true
        errorMessage = nil
        
        let baseURL = "https://moneyvate-server-e465a01b5e1c.herokuapp.com"
        let endpoint = "/create-payment-intent"
        let urlString = baseURL + endpoint
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            errorMessage = "Invalid URL"
            completion(false)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(currentEnvironment == .production ? "production" : "development", forHTTPHeaderField: "X-Environment")

        let body = ["amount": amount]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        print("Sending request to server...")
        URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                    completion(false)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("Server responded with status code: \(httpResponse.statusCode)")
                }
                
                guard let data = data else {
                    print("No data received from the server")
                    self?.errorMessage = "No data received from the server"
                    completion(false)
                    return
                }
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let clientSecret = json["clientSecret"] as? String,
                       let publishableKey = json["publishableKey"] as? String {
                      print("Successfully extracted client secret and publishable key")
                      var configuration = PaymentSheet.Configuration()
                      configuration.merchantDisplayName = "Moneyvate"
                      configuration.defaultBillingDetails.name = "Jane Doe" // Add a default name
                      StripeAPI.defaultPublishableKey = publishableKey
                      self?.paymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
                      print("PaymentSheet created successfully")
                      completion(true)
                    } else {
                      print("Client secret or publishable key not found in JSON response")
                      self?.errorMessage = "Invalid response from the server"
                      completion(false)
                    }
                  } catch {
                    print("Error parsing server response: \(error.localizedDescription)")
                    self?.errorMessage = "Error parsing server response: \(error.localizedDescription)"
                    completion(false)
                }
            }
        }.resume()
    }

    func preparePaymentSheet(amount: Int, completion: @escaping (PaymentSheet?) -> Void) {
        guard isNetworkAvailable else {
            errorMessage = "No network connection. Please check your internet and try again."
            completion(nil)
            return
        }
        isLoading = true
        errorMessage = nil
        
        createPaymentIntent(amount: amount) { [weak self] success in
            DispatchQueue.main.async {
                self?.isLoading = false
                if success {
                    completion(self?.paymentSheet)
                } else {
                    self?.errorMessage = "Failed to create payment intent"
                    completion(nil)
                }
            }
        }
    }
    
    enum Environment {
        case development
        case production
    }

    @Published var currentEnvironment: Environment = .development

    func fetchEnvironment() {
        let url = URL(string: "https://moneyvate-server-e465a01b5e1c.herokuapp.com/environment")!
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: String],
                  let environment = json["environment"] else {
                print("Failed to fetch environment")
                return
            }
            DispatchQueue.main.async {
                self?.currentEnvironment = environment == "production" ? .production : .development
                print("Current environment: \(environment)")  // Add this line
            }
        }.resume()
    }
}
