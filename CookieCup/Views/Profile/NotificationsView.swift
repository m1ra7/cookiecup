import SwiftUI

@MainActor
struct NotificationsView: View {
    @Environment(\.copy) private var copy
    @State private var notifications: [InboxNotification] = []
    @State private var cursor: String?
    @State private var loading = false
    @State private var errorKey: String?
    @State private var order: Order?
    var body: some View {
        SettingsPage(title: "platform.notifications") {
            NavigationLink { NotificationSettingsView() } label: { Label(copy.text("settings"), systemImage: "gearshape") }
            if AccountStore.shared.account == nil { SettingsLoginPrompt() }
            else {
                if notifications.isEmpty && !loading { SettingsNote(key: "platform.noNotifications") }
                ForEach(notifications) { item in
                    Button { Task { await open(item) } } label: {
                        CafePanel {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(item.titles[copy.language] ?? item.titles["en"] ?? "CookieCup").font(.headline)
                                    Spacer()
                                    if item.readAt == nil { Circle().fill(CafePalette.cream).frame(width: 7, height: 7) }
                                }
                                Text(item.bodies[copy.language] ?? item.bodies["en"] ?? "").font(.subheadline).foregroundColor(CafePalette.secondary)
                                Text(item.createdAt, style: .relative).font(.caption).foregroundColor(CafePalette.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(.plain)
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if cursor != nil { Button(copy.text("platform.loadMore")) { Task { await load(more: true) } }.disabled(loading) }
                SettingsError(key: errorKey)
                if errorKey != nil { Button(copy.text("platform.retry")) { Task { await load() } } }
            }
        }.task { await load() }.refreshable { await load() }
            .sheet(item: $order) { OrderDetailView(order: $0) }
    }
    private func load(more: Bool = false) async {
        guard AccountStore.shared.account != nil, !loading else { return }
        guard APIClient.shared.supportsPlatform else { errorKey = "platform.awaitingActivation"; return }
        loading = true
        do {
            var query = [URLQueryItem(name: "limit", value: "20")]
            if more, let cursor = cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page: InboxPage = try await APIClient.shared.getV2("me/notifications", query: query)
            if more { notifications += page.notifications } else { notifications = page.notifications }
            cursor = page.nextCursor; errorKey = nil
        } catch { errorKey = settingsErrorKey(error) }
        loading = false
    }
    private func open(_ item: InboxNotification) async {
        do {
            let _: CloudAck = try await APIClient.shared.sendV2("me/notifications/" + item.id.uuidString + "/read", body: [String: String]())
            if let index = notifications.firstIndex(where: { $0.id == item.id }) { notifications[index].readAt = Date() }
            if let id = item.data["orderID"] { order = try await APIClient.shared.getV2("me/orders/" + id) }
        } catch { errorKey = settingsErrorKey(error) }
    }
}
@MainActor
struct NotificationSettingsView: View {
    @Environment(\.copy) private var copy
    @ObservedObject private var push = PushNotifications.shared
    @State private var consent = false
    @State private var loaded = false
    @State private var busy = false
    @State private var errorKey: String?
    var body: some View {
        SettingsPage(title: "platform.notifications") {
            if AccountStore.shared.account == nil { SettingsLoginPrompt() }
            else {
                CafePanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(copy.text("platform.marketing"), isOn: $consent).disabled(!loaded || busy)
                            .onChange(of: consent) { _ in if loaded { Task { await save() } } }
                        SettingsNote(key: "platform.marketingHint")
                        Button(copy.text("platform.enablePush")) { Task { await push.enable() } }.buttonStyle(CafePrimaryButton()).disabled(!push.available)
                        if !push.available { SettingsNote(key: "platform.pushSetup") }
                        SettingsError(key: errorKey ?? push.errorKey)
                    }
                }
            }
        }.task {
            guard AccountStore.shared.account != nil else { return }
            guard APIClient.shared.supportsPlatform else { errorKey = "platform.awaitingActivation"; return }
            do { let preferences: NotificationPreferences = try await APIClient.shared.getV2("me/preferences"); consent = preferences.marketingConsent; await Task.yield(); loaded = true }
            catch { errorKey = settingsErrorKey(error) }
            await push.registerIfAllowed()
        }
    }
    private func save() async {
        busy = true
        do { let _: NotificationPreferences = try await APIClient.shared.sendV2("me/preferences", method: "PUT", body: NotificationPreferences(marketingConsent: consent, locale: copy.language)); errorKey = nil }
        catch { errorKey = settingsErrorKey(error) }
        busy = false
    }
}
