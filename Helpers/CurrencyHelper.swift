import Foundation

struct CurrencyHelper {
    static func format(amount: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }
    
    static func currencySymbol(for currencyCode: String) -> String? {
        let locale = locales.first {
            let localeCurrencyCode: String?
            if #available(iOS 16.0, *) {
                localeCurrencyCode = $0.currency?.identifier
            } else {
                localeCurrencyCode = $0.currencyCode
            }
            return localeCurrencyCode == currencyCode
        }
        return locale?.currencySymbol
    }
    
    private static let locales = Locale.availableIdentifiers.map { Locale(identifier: $0) }
}

