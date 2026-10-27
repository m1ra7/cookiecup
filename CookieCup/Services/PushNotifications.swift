import SwiftUI
import UserNotifications
import UIKit
import Combine

struct NotificationPreferences: Codable { var marketingConsent: Bool; var locale: String }
struct PlatformCapabilities: Decodable { let pushAvailable: Bool; let payments: String; let deliveryEnabled: Bool }
struct InboxNotification: Decodable, Identifiable {
    let id: UUID
    let titles: [String: String]
    let bodies: [String: String]
    let data: [String: String]
    let marketing: Bool
    let createdAt: Date
    var readAt: Date?
}
struct InboxPage: Decodable { let notifications: [InboxNotification]; let nextCursor: String? }

@MainActor
final class PushNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotifications()
    @Published var orderID: UUID?
    @Published private(set) var available = false
    @Published private(set) var errorKey: String?
    private var token: String?
    private var registeredID: UUID?
    private var accountID: String?
    private var observer: AnyCancellable?
    private var registration: Task<Void, Never>?
    private let installationID: UUID = {
        if let saved = UserDefaults.standard.string(forKey: "cookiecup.installationID"), let id = UUID(uuidString: saved) { return id }
        let id = UUID(); UserDefaults.standard.set(id.uuidString, forKey: "cookiecup.installationID"); return id
    }()
    override private init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        observer = AccountStore.shared.$account.sink { [weak self] account in
            guard let self = self, self.accountID != account?.id else { return }
            self.accountID = account?.id; self.registration?.cancel()
            if account != nil { self.registration = Task { await self.registerIfAllowed() } }
        }
    }
    func registerIfAllowed() async {
        guard APIClient.shared.supportsPlatform, APIClient.shared.hasCredential else { return }
        do {
            let capabilities: PlatformCapabilities = try await APIClient.shared.getV2("capabilities")
            available = capabilities.pushAvailable
            guard available else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { UIApplication.shared.registerForRemoteNotifications() }
        } catch { errorKey = settingsErrorKey(error) }
    }
    func enable() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { errorKey = "platform.pushDenied"; return }
            await registerIfAllowed()
        } catch { errorKey = settingsErrorKey(error) }
    }
    func receivedToken(_ data: Data) {
        token = data.map { String(format: "%02x", $0) }.joined()
        registration?.cancel(); registration = Task { await uploadToken() }
    }
    private func uploadToken() async {
        guard let token = token, let user = AccountStore.shared.account?.id else { return }
        struct Registration: Encodable { let id: UUID; let token: String; let environment: String; let locale: String }
        struct Result: Decodable { let ok: Bool; let id: UUID }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            let result: Result = try await APIClient.shared.sendV2("me/devices", body: Registration(id: registeredID ?? installationID, token: token, environment: environment, locale: UserDefaults.standard.string(forKey: "language") ?? "en"))
            if AccountStore.shared.account?.id == user && !Task.isCancelled { registeredID = result.id; errorKey = nil }
        } catch { if !Task.isCancelled { errorKey = settingsErrorKey(error) } }
    }
    func unregister() async {
        registration?.cancel()
        if let id = registeredID {
            let _: CloudAck? = try? await APIClient.shared.sendV2("me/devices/" + id.uuidString, method: "DELETE", body: [String: String]())
        }
        registeredID = nil
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let value = response.notification.request.content.userInfo["orderID"] as? String
        Task { @MainActor in self.orderID = value.flatMap(UUID.init(uuidString:)) }
        completionHandler()
    }
}
@MainActor
final class CookieCupAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { PushNotifications.shared.receivedToken(deviceToken) }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { /* The settings page explains configuration requirements. No token or credentials are logged. */ }
}
