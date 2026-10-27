import Foundation

struct CafeAddress: Identifiable, Codable, Equatable {
    var id = UUID()
    var label = ""
    var recipient = ""
    var street = ""
    var city = ""
    var postalCode = ""
    var country = ""
    var phone = ""
    var summary: String { [recipient, street, postalCode + " " + city, country, phone].filter { !$0.isEmpty }.joined(separator: "\n") }
    var isValid: Bool { [label, recipient, street, city, postalCode, country].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
}

// A display reference only: never a payment token, PAN or CVV.
struct CafeCard: Identifiable, Codable, Equatable {
    var id = UUID()
    let holder: String
    let brand: String
    let lastFour: String
    let month: Int
    let year: Int
    var expiry: String { String(format: "%02d/%02d", month, year % 100) }
}

struct CafeAccount: Identifiable, Codable {
    let id: String
    var name: String
    let email: String
    var addresses: [CafeAddress] = []
    var cards: [CafeCard] = []
    var defaultAddressID: UUID?
    var defaultCardID: UUID?
}

enum AccountFailure: String, Error {
    case invalid = "settings.invalid"
    case credentials = "settings.credentials"
    case exists = "settings.exists"
    case storage = "settings.storageError"
    case loginRequired = "settings.loginRequired"
}
