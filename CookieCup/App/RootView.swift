import SwiftUI

@MainActor
struct RootView: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack { HomeView().navigationDestination(for: Product.self) { ProductDetail(product: $0) } }
                .tabItem { Label(copy.text("home"), systemImage: "house.fill") }.tag(0)
            NavigationStack { MenuView().navigationDestination(for: Product.self) { ProductDetail(product: $0) } }
                .tabItem { Label(copy.text("menu"), systemImage: "square.grid.2x2.fill") }.tag(1)
            NavigationStack { FavoritesView().navigationDestination(for: Product.self) { ProductDetail(product: $0) } }
                .tabItem { Label(copy.text("favorites"), systemImage: "heart.fill") }.tag(2)
            NavigationStack { CartView() }
                .tabItem { Label(copy.text("cart"), systemImage: "bag.fill") }.badge(store.count).tag(3)
            NavigationStack { ProfileView() }
                .tabItem { Label(copy.text("profile"), systemImage: "person.crop.circle.fill") }.tag(4)
        }.disabled(store.placingOrder)
        .compatibleFeedback(.success, trigger: store.count)
        .task { await APIClient.shared.checkPlatform(); await AccountStore.shared.restore(); await store.refreshCatalog() }
        .safeAreaInset(edge: .bottom) {
            if let key = store.syncErrorKey {
                HStack {
                    Text(copy.text(key)).font(.caption)
                    Spacer()
                    Button(copy.text("cloud.retry")) { Task { await store.retrySync() } }
                }.padding(12).foregroundColor(CafePalette.cream).background(CafePalette.header)
            }
        }
        .overlay(alignment: .top) {
            if let key = store.toastKey {
                Label(copy.text(key), systemImage: "checkmark.circle.fill").font(.subheadline.bold())
                    .padding().background(.regularMaterial, in: Capsule()).padding(.top, 8).allowsHitTesting(false)
            }
        }
    }
}
