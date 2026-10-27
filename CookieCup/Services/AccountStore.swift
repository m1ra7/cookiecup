import Foundation
import Combine

@MainActor final class AccountStore: ObservableObject {
    static let shared = AccountStore()
    @Published private(set) var account: CafeAccount?
    @Published private(set) var restoring = false
    @Published var errorKey: String?
    private let api = APIClient.shared
    private var restored = false
    private init() {}
    static func normalizedEmail(_ value: String) -> String {
        let edgeCharacters = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "\u{200B}\u{FEFF}"))
        return value.trimmingCharacters(in: edgeCharacters).lowercased()
    }
    static func validEmail(_ value: String) -> Bool {
        let email = normalizedEmail(value)
        guard email.utf8.count <= 254 else { return false }
        return email.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
                           options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func validPassword(_ value: String) -> Bool { value.count >= 10 && value.utf8.count <= 256 }
    func restore() async {
        guard !restoring else { return }
        guard !restored || (account == nil && api.hasCredential) else { return }
        restored = true
        guard api.hasCredential else { return }
        restoring = true
        do { account = try await api.get("me"); errorKey = nil }
        catch {
            errorKey = settingsErrorKey(error)
            if (error as? CloudFailure)?.code == "loginRequired" { try? api.clearCredential() }
        }
        restoring = false
    }
    func authenticate(name: String, email: String, password: String, registering: Bool) async throws {
        let mail = Self.normalizedEmail(email)
        guard Self.validEmail(mail), !password.isEmpty else { throw AccountFailure.invalid }
        let response: CloudSession = try await api.send(registering ? "auth/register" : "auth/login", body: ["name": name, "email": mail, "password": password])
        try api.saveCredential(response.credential)
        account = response.account; errorKey = nil
    }
    func logout() async throws {
        await PushNotifications.shared.unregister()
        do { let _: CloudAck = try await api.send("me/logout", body: [String: String]()) }
        catch { if (error as? CloudFailure)?.code != "loginRequired" { throw error } }
        try api.clearCredential(); account = nil; errorKey = nil
    }
    func rename(_ name: String) async throws {
        account = try await api.send("me/name", method: "PATCH", body: ["name": name])
    }
    func changePassword(current: String, new: String) async throws {
        guard Self.validPassword(new) else { throw AccountFailure.invalid }
        let result: CloudCredential = try await api.send("me/password", body: ["current": current, "new": new])
        try api.saveCredential(result.credential)
    }
    func deleteAccount(password: String) async throws {
        let _: CloudAck = try await api.send("me/delete", body: ["password": password])
        try api.clearCredential(); account = nil
    }
    func saveAddress(_ address: CafeAddress) async throws {
        guard address.isValid else { throw AccountFailure.invalid }
        try await update {
            if let index = $0.addresses.firstIndex(where: { $0.id == address.id }) { $0.addresses[index] = address }
            else { $0.addresses.append(address) }
            if $0.defaultAddressID == nil { $0.defaultAddressID = address.id }
        }
    }
    func removeAddress(_ id: UUID) async throws { try await update { $0.addresses.removeAll { $0.id == id }; if $0.defaultAddressID == id { $0.defaultAddressID = $0.addresses.first?.id } } }
    func defaultAddress(_ id: UUID) async throws { try await update { $0.defaultAddressID = id } }
    func saveCard(_ card: CafeCard) async throws {
        try await update {
            guard !$0.cards.contains(where: { $0.lastFour == card.lastFour && $0.brand == card.brand && $0.month == card.month && $0.year == card.year }) else { throw AccountFailure.exists }
            $0.cards.append(card); if $0.defaultCardID == nil { $0.defaultCardID = card.id }
        }
    }
    func removeCard(_ id: UUID) async throws { try await update { $0.cards.removeAll { $0.id == id }; if $0.defaultCardID == id { $0.defaultCardID = $0.cards.first?.id } } }
    func defaultCard(_ id: UUID) async throws { try await update { $0.defaultCardID = id } }
    private func update(_ change: (inout CafeAccount) throws -> Void) async throws {
        guard var current = account else { throw AccountFailure.loginRequired }
        let id = current.id
        try change(&current)
        let result: CafeAccount = try await api.send("me/profile", method: "PUT", body: current)
        guard account?.id == id else { return }
        account = result
    }
    func requestRecovery(email: String) async throws {
        let _: CloudAck = try await api.send("auth/recovery", body: ["email": Self.normalizedEmail(email)])
    }
    func resetPassword(email: String, otp: String, password: String) async throws {
        let _: CloudAck = try await api.send("auth/reset", body: ["email": Self.normalizedEmail(email), "otp": otp, "password": password])
    }
}

enum CardValidation {
    static func digits(_ value: String) -> String { value.filter { $0.isASCII && $0.isNumber } }
    static func validNumber(_ value: String) -> Bool {
        guard (12...19).contains(value.count), value == digits(value), Set(value).count > 1 else { return false }
        let sum = value.reversed().enumerated().reduce(0) { result, item in
            var digit = item.element.wholeNumberValue ?? 0
            if item.offset % 2 == 1 { digit *= 2; if digit > 9 { digit -= 9 } }
            return result + digit
        }
        return sum % 10 == 0
    }
    static func validExpiry(month: Int, year: Int, now: Date = Date()) -> Bool {
        let calendar = Calendar(identifier: .gregorian)
        let currentYear = calendar.component(.year, from: now)
        let currentMonth = calendar.component(.month, from: now)
        return (1...12).contains(month) && (currentYear...currentYear + 20).contains(year)
            && (year > currentYear || month >= currentMonth)
    }
    static func brand(_ number: String) -> String {
        if number.hasPrefix("4") { return "Visa" }
        let firstTwo = Int(number.prefix(2)) ?? 0
        let firstFour = Int(number.prefix(4)) ?? 0
        if (51...55).contains(firstTwo) || (2221...2720).contains(firstFour) { return "Mastercard" }
        if number.hasPrefix("34") || number.hasPrefix("37") { return "American Express" }
        if number.hasPrefix("9792") { return "Troy" }
        return ""
    }
}
