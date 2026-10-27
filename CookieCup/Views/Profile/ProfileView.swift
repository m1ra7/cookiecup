import SwiftUI

@MainActor
struct ProfileView: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    @ObservedObject private var accounts = AccountStore.shared
    @State private var showSettings = false
    @State private var showAllOrders = false
    @State private var detailOrder: Order?
    private var visibleOrders: [Order] {
        showAllOrders ? store.state.orders : Array(store.state.orders.prefix(5))
    }
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 27) {
                ProfileAccountSection()
                if accounts.account != nil { historySection }
            }.padding(.horizontal, 22).padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .cafePage()
        .refreshable { await store.retrySync() }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .sheet(isPresented: $showSettings) { CookieCupSettingsView() }
        .sheet(item: $detailOrder) { order in OrderDetailView(order: order) }
        .onChange(of: accounts.account?.id) { _ in
            showAllOrders = false
            detailOrder = nil
        }
    }
    private var header: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Spacer(minLength: 4)
            Text(copy.text("profile")).font(CafeTypography.script(33))
                .lineLimit(1).minimumScaleFactor(0.65)
            Spacer(minLength: 4)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 21))
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(copy.text("settings"))
        }.foregroundColor(CafePalette.cream)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(CafePalette.header.ignoresSafeArea(edges: .top))
    }
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                sectionLabel("orders")
                Spacer()
                Text("\(store.state.orders.count)").font(.caption).foregroundColor(CafePalette.secondary)
            }
            if visibleOrders.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "clock").foregroundColor(CafePalette.secondary)
                    Text(copy.text("noOrders")).font(.subheadline).foregroundColor(CafePalette.secondary)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CafePalette.surface, in: RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleOrders) { order in
                        Button { detailOrder = order } label: {
                            HStack(spacing: 0) {
                                SettingsOrderRow(order: order)
                                Image(systemName: "chevron.right").font(.caption)
                                    .foregroundColor(CafePalette.secondary).padding(.trailing, 16)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(copy.text("viewOrder") + ", " + copy.money(order.totalCents))
                        if order.id != visibleOrders.last?.id {
                            Rectangle().fill(CafePalette.cream.opacity(0.08)).frame(height: 1).padding(.horizontal, 16)
                        }
                    }
                }.background(CafePalette.surface, in: RoundedRectangle(cornerRadius: 20))
                if showAllOrders && store.orderCursor != nil {
                    Button(copy.text("platform.loadMore")) { Task { await store.loadMoreOrders() } }.disabled(store.ordersLoading)
                }
                if store.state.orders.count > 5 {
                    Button(copy.text(showAllOrders ? "showLess" : "showAllOrders")) { showAllOrders.toggle() }
                        .font(.subheadline).foregroundColor(CafePalette.cream)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }
    private func sectionLabel(_ key: String) -> some View {
        Text(copy.text(key)).font(.system(size: 14, weight: .semibold)).foregroundColor(CafePalette.cream)
    }
}

@MainActor
private struct SettingsOrderRow: View {
    @Environment(\.copy) private var copy
    let order: Order
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(order.customer).font(.subheadline.bold()).foregroundColor(.white)
                    Text(order.date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(copy.locale)))
                        .font(.caption).foregroundColor(CafePalette.secondary)
                }
                Spacer(minLength: 0)
                Text(copy.money(order.totalCents)).font(.subheadline.bold()).foregroundColor(CafePalette.cream)
            }
            Text(copy.text(order.status.map { "status." + $0 } ?? "localOrder")).font(.caption2).foregroundColor(CafePalette.secondary)
            if !order.note.isEmpty { Text(order.note).font(.caption).foregroundColor(CafePalette.secondary) }
        }.padding(16)
    }
}

@MainActor
struct OrderDetailView: View {
    @EnvironmentObject private var store: ShopStore
    @State private var statusOverride: String?
    @State private var errorKey: String?
    @State private var busy = false
    @Environment(\.copy) private var copy
    @Environment(\.dismiss) private var dismiss
    let order: Order
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    summary
                    if let status = statusOverride ?? order.status {
                        Text(copy.text("status." + status)).font(.headline).foregroundColor(CafePalette.cream)
                        if status == "pending" {
                            Button(copy.text("cloud.cancelOrder"), role: .destructive) { cancelOrder() }.disabled(busy)
                        }
                    }
                    SettingsError(key: errorKey)
                    if let items = order.items, !items.isEmpty {
                        ForEach(items) { item in OrderProductRow(item: item) }
                    } else {
                        CafePanel {
                            Text(copy.text("legacyOrderDetails"))
                                .font(.subheadline).foregroundColor(CafePalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !order.note.isEmpty {
                        CafePanel {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(copy.text("orderNote")).font(.headline)
                                Text(order.note).font(.subheadline)
                            }.foregroundColor(CafePalette.cream)
                        }
                    }
                    Text(copy.text("demoNotice")).font(.caption).foregroundColor(CafePalette.secondary)
                }.padding(20)
            }
            .cafePage()
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Text(copy.text("orderDetails")).font(CafeTypography.script(28))
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .buttonStyle(.plain).accessibilityLabel(copy.text("settingsClose"))
                }.foregroundColor(CafePalette.cream).padding(.horizontal, 20).padding(.vertical, 8)
                    .background(CafePalette.header.ignoresSafeArea(edges: .top))
            }
        }.preferredColorScheme(.dark)
    }
    private func cancelOrder() {
        guard !busy else { return }; busy = true
        Task { @MainActor in
            do { try await store.cancelOrder(order); statusOverride = "cancelled" }
            catch { errorKey = settingsErrorKey(error) }
            busy = false
        }
    }
    private var summary: some View {
        CafePanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(order.customer).font(.headline)
                Text(order.date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute().locale(copy.locale)))
                    .font(.caption).foregroundColor(CafePalette.secondary)
                HStack { Text(copy.text("quantity")); Spacer(); Text("\(order.itemCount)") }
                HStack { Text(copy.text("total")); Spacer(); Text(copy.money(order.totalCents)).bold() }
                Text(copy.text("orderPricesSaved")).font(.caption).foregroundColor(CafePalette.secondary)
            }.foregroundColor(CafePalette.cream)
        }
    }
}
@MainActor
private struct OrderProductRow: View {
    @Environment(\.copy) private var copy
    let item: OrderItem
    var body: some View {
        CafePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    CachedProductImage(imageName: item.imageName, imagePath: item.imagePath).scaledToFit().frame(width: 70, height: 80)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(item.names[copy.language] ?? item.names["en"] ?? item.productID)
                            .font(.headline).fixedSize(horizontal: false, vertical: true)
                        if item.isCoffee {
                            Text([item.options.size, item.options.milk, item.options.sugar, item.options.extra]
                                .map { copy.text("option." + $0) }.joined(separator: " · "))
                                .font(.caption).foregroundColor(CafePalette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("\(item.quantity) × " + copy.money(item.unitCents)).font(.subheadline)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Text(copy.text("total")).font(.caption); Spacer(); Text(copy.money(item.totalCents)).font(.headline) }
            }.foregroundColor(CafePalette.cream)
        }
    }
}
