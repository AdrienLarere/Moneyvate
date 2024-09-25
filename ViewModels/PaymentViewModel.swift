import SwiftUI
import UIKit
import Stripe
import StripePaymentSheet
import Combine
import Network
import FirebaseAuth
import PassKit

class PaymentViewModel: ObservableObject {
    @Published var stripePaymentSheet: PaymentSheet?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isNetworkAvailable = true
    @Published var paymentIntentId: String?
    private let monitor = NWPathMonitor()
    
    // Firebase ID Token
    private var idToken: String?
    
    init() {
        startNetworkMonitoring()
        fetchEnvironment()
        fetchIdToken()
    }
    
//    enum PaymentMethod: String, CaseIterable, Identifiable {
//        case applePay = "Apple Pay"
//        case card = "Credit Card"
//        
//        var id: String { self.rawValue }
//    }
    
    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isNetworkAvailable = path.status == .satisfied
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    // Fetch the Firebase ID Token
    private func fetchIdToken() {
        if let user = Auth.auth().currentUser {
            print("User is authenticated: \(user.uid)")
            user.getIDToken { [weak self] idToken, error in
                if let error = error {
                    print("Error fetching ID token: \(error.localizedDescription)")
                    self?.errorMessage = "Authentication error. Please log in again."
                } else {
                    self?.idToken = idToken
                    print("Fetched ID Token: \(idToken ?? "No ID Token")")
                }
            }
        } else {
            print("User not authenticated.")
            self.errorMessage = "User not authenticated. Please log in."
        }
    }
    
    func createPaymentIntent(amount: Int, currencyCode: String, completion: @escaping (Bool) -> Void) {
            print("Creating payment intent for amount: \(amount) in currency: \(currencyCode)")
            isLoading = true
            errorMessage = nil
            
            let baseURL = "\(AppConfig.serverURL)"
            let endpoint = "/create-payment-intent"
            let urlString = baseURL + endpoint
            
            guard let url = URL(string: urlString), let idToken = idToken else {
                print("Invalid URL or missing ID token")
                errorMessage = "Invalid URL or authentication error"
                completion(false)
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(AppConfig.environment == .production ? "production" : "development", forHTTPHeaderField: "X-Environment")
            
            let body: [String: Any] = ["amount": amount, "currency": currencyCode]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            
            URLSession.shared.dataTask(with: request) { [weak self] (data, response, error) in
                DispatchQueue.main.async {
                    self?.isLoading = false
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    self?.handleError(message: "Network error: \(error.localizedDescription)")
                    completion(false)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid response received from the server")
                    self?.handleError(message: "Invalid response from the server.")
                    completion(false)
                    return
                }
                
                print("Server responded with status code: \(httpResponse.statusCode)")
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    print("Server returned an error status code: \(httpResponse.statusCode)")
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data, options: []),
                       let dict = json as? [String: Any],
                       let serverErrorMessage = dict["error"] as? String {
                        self?.handleError(message: serverErrorMessage)
                    } else {
                        self?.handleError(message: "Server error occurred. Please try again later.")
                    }
                    completion(false)
                    return
                }
                
                guard let data = data else {
                    print("No data received from the server")
                    self?.handleError(message: "No data received from the server")
                    completion(false)
                    return
                }
                
                if let dataString = String(data: data, encoding: .utf8) {
                    print("Response Data: \(dataString)")
                } else {
                    print("Unable to decode response data")
                }
                
                    do {
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    if let dict = json as? [String: Any],
                       let clientSecret = dict["clientSecret"] as? String,
                       let paymentIntentId = dict["paymentIntentId"] as? String {
                        print("Successfully extracted client secret and payment intent ID")
                        
                        var configuration = PaymentSheet.Configuration()
                        configuration.merchantDisplayName = "Moneyvate"
                        configuration.applePay = .init(merchantId: "merchant.com.moneyvate", merchantCountryCode: "US")
                        configuration.defaultBillingDetails.name = "Jane Doe" // Replace with the user's name if available
                        StripeAPI.defaultPublishableKey = AppConfig.stripePublishableKey
                        self?.stripePaymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)

                        self?.paymentIntentId = paymentIntentId
                        print("PaymentSheet created successfully")
                        completion(true)
                    } else {
                        self?.handleError(message: "Invalid response from the server.")
                        completion(false)
                    }
                } catch {
                    self?.handleError(message: "Error parsing server response.")
                    completion(false)
                }
            }
        }.resume()
    }
    
    func refundPayment(paymentIntentId: String, amount: Int, completion: @escaping (Bool, String?) -> Void) {
        guard isNetworkAvailable else {
            errorMessage = "No network connection. Please check your internet and try again."
            completion(false, "No network connection.")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        let baseURL = "\(AppConfig.serverURL)"
        let endpoint = "/refund-payment"
        let urlString = baseURL + endpoint
        
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            errorMessage = "Invalid URL"
            completion(false, "Invalid URL.")
            return
        }
        
        guard let idToken = idToken else {
            print("ID Token is not available")
            errorMessage = "Authentication error. Please log in again."
            completion(false, "Authentication error.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(currentEnvironment == .production ? "production" : "development", forHTTPHeaderField: "X-Environment")
        
        let body: [String: Any] = [
            "paymentIntentId": paymentIntentId,
            "amount": amount
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        print("Sending refund request to server...")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    print("Network error: \(error.localizedDescription)")
                    completion(false, "Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Invalid response")
                    completion(false, "Invalid response from server.")
                    return
                }
                
                if httpResponse.statusCode == 200 {
                    // Refund successful
                    print("Refund successful")
                    completion(true, nil)
                } else {
                    // Handle error response
                    if let data = data,
                       let json = try? JSONSerialization.jsonObject(with: data, options: []),
                       let dict = json as? [String: Any],
                       let errorMessage = dict["error"] as? String {
                        print("Refund error: \(errorMessage)")
                        completion(false, errorMessage)
                    } else {
                        print("Refund failed with status code: \(httpResponse.statusCode)")
                        completion(false, "Refund failed with status code: \(httpResponse.statusCode)")
                    }
                }
            }
        }.resume()
    }
    
    @Published var currentEnvironment: Env = AppConfig.environment
    
    func fetchEnvironment() {
        let url = URL(string: "\(AppConfig.serverURL)/environment")!
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data, options: []),
                  let dict = json as? [String: String],
                  let environment = dict["environment"] else {
                print("Failed to fetch environment")
                return
            }
            DispatchQueue.main.async {
                self?.currentEnvironment = environment == "production" ? .production : .development
                print("Current environment: \(environment)")
            }
        }.resume()
    }
    
    private func handleError(message: String) {
        self.errorMessage = message
        print("Error: \(message)")
    }
}
