import SwiftUI

@main @MainActor struct CookieCupApp: App {
    @UIApplicationDelegateAdaptor(CookieCupAppDelegate.self) private var appDelegate
    @StateObject private var push = PushNotifications.shared
    @State private var pushedOrder: Order?
    @StateObject private var store = ShopStore()
    @AppStorage("language") private var language = Locale.preferredLanguages.first.map { String($0.prefix(2)) }.flatMap { ["tr", "de", "en"].contains($0) ? $0 : nil } ?? "en"
    init() { CafeTypography.registerFonts() }

    var body: some Scene {
        WindowGroup {
            CookieCupStartupView().environmentObject(store).environment(\.copy, Copy(language: language))
                .environment(\.locale, Locale(identifier: language))
                .preferredColorScheme(.dark)
                .tint(Theme.caramel)
                .onChange(of: push.orderID) { id in
                    guard let id = id else { return }
                    Task { @MainActor in
                        do { pushedOrder = try await APIClient.shared.getV2("me/orders/" + id.uuidString) }
                        catch { store.syncErrorKey = settingsErrorKey(error) }
                        push.orderID = nil
                    }
                }
                .sheet(item: $pushedOrder) { OrderDetailView(order: $0) }
        }
    }
}

private struct CookieCupStartupView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingLaunch = true
    var body: some View {
        ZStack {
            RootView().accessibilityHidden(showingLaunch)
            if showingLaunch {
                ZStack {
                    Color("LaunchBackground").ignoresSafeArea()
                    Image("LaunchWordmark").resizable().scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 80)
                        .padding(.horizontal, 24)
                        .accessibilityLabel("CookieCup")
                }.transition(.opacity).zIndex(1)
            }
        }
        .task {
            do { try await Task.sleep(nanoseconds: 900_000_000) }
            catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { showingLaunch = false }
        }
    }
}
