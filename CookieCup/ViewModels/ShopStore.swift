import Foundation
import Combine
import CryptoKit

@MainActor final class ShopStore: ObservableObject {
    @Published var state: SavedState
    @Published var selectedTab = 0
    @Published var toastKey: String?
    @Published var syncErrorKey: String?
    @Published private(set) var placingOrder = false
    @Published private(set) var syncing = false
    @Published private(set) var homeLayout = HomeLayout.cached()
    private var homeLayoutTime = Date.distantPast
    private var homeLayoutLoading = false
    func refreshHomeLayout(force: Bool = false) async {
        guard !homeLayoutLoading, force || Date().timeIntervalSince(homeLayoutTime) > 15 else { return }
        homeLayoutLoading = true
        defer { homeLayoutLoading = false }
        await api.checkPlatform()
        guard api.supportsPlatform else { return }
        do {
            let layout: HomeLayout = try await api.getV2("home-layout")
            let changed = layout.version != homeLayout.version
            homeLayout = layout
            homeLayoutTime = Date()
            if let data = try? JSONEncoder().encode(layout) { UserDefaults.standard.set(data, forKey: "homeLayout.cache") }
            if changed || force { menuCatalogTime = .distantPast; offersTime = .distantPast }
            if layout.sections.contains(where: { $0.kind == "products" }) { _ = try await completeMenuCatalog() }
            if force { offersTime = .distantPast }
            if layout.sections.contains(where: { $0.kind == "deals" }) { await loadMenuOffers() }
        } catch {
            // Retain the last published layout during connection failures.
            if homeLayout.version == 0 { await loadMenuOffers() }
        }
    }
    @Published private(set) var menuOffers: [MenuOffer] = []
    @Published private(set) var selectedMenuOffer: MenuOffer?
    @Published var cartCouponCode = "" {
        didSet { couponQuote = nil; couponErrorKey = nil }
    }
    @Published private(set) var couponQuote: CartQuote?
    @Published private(set) var couponErrorKey: String?
    @Published private(set) var applyingCoupon = false
    private var couponRequest = UUID()
    var cartContentsKey: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = (try? encoder.encode(state.cart)) ?? Data()
        return data.base64EncodedString() + (AccountStore.shared.account?.id ?? "guest")
    }
    struct CartQuoteRequest: Encodable {
        let lines: [CartLine]
        let promotionCode: String
        let fulfillment = "pickup"
    }
    func removeCoupon() {
        couponRequest = UUID(); applyingCoupon = false
        cartCouponCode = ""; selectedMenuOffer = nil
    }
    func applyCartCoupon() async {
        let code = cartCouponCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        couponQuote = nil; couponErrorKey = nil
        guard !code.isEmpty, !state.cart.isEmpty else { return }
        guard AccountStore.shared.account != nil else { couponErrorKey = "cartCouponLogin"; return }
        let token = UUID(); couponRequest = token
        let contents = cartContentsKey
        applyingCoupon = true
        defer { if couponRequest == token { applyingCoupon = false } }
        do {
            let result: CartQuote = try await api.sendV2("me/quote", body: CartQuoteRequest(lines: state.cart, promotionCode: code))
            guard couponRequest == token, contents == cartContentsKey,
                  code == cartCouponCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else { return }
            couponQuote = result
        } catch {
            guard couponRequest == token, contents == cartContentsKey else { return }
            couponErrorKey = settingsErrorKey(error)
        }
    }
    private var offersTime = Date.distantPast
    private var offersLoading = false
    struct MenuOffersResponse: Decodable { let offers: [MenuOffer] }
    var menuPromotionCode: String? {
        guard let offer = selectedMenuOffer, offer.available,
              offer.productIDs.allSatisfy({ id in state.cart.contains { $0.productID == id && $0.quantity > 0 } }) else { return nil }
        return offer.code
    }
    func loadMenuOffers() async {
        guard !offersLoading else { return }
        offersLoading = true
        defer { offersLoading = false }
        await api.checkPlatform()
        guard api.supportsPlatform else { return }
        guard Date().timeIntervalSince(offersTime) > 60 else { return }
        do {
            _ = try await completeMenuCatalog()
            let response: MenuOffersResponse = try await api.getV2("menu-offers")
            menuOffers = response.offers
            offersTime = Date()
        } catch { menuOffers = [] }
    }
    func addMenu(_ offer: MenuOffer) {
        guard offer.available else { return }
        for product in offer.products {
            let current = state.cart.filter { $0.productID == product.id }.reduce(0) { $0 + $1.quantity }
            guard current < 99, product.stock.map({ $0 >= current + 1 }) ?? true else { showToast("cloud.outOfStock"); return }
        }
        for product in offer.products { add(product) }
        selectedMenuOffer = offer
        cartCouponCode = offer.code
        selectedTab = 3
    }
    private let persistence = Persistence()
    private let api = APIClient.shared
    private let bundledImages: [String: String]
    private var guest: SavedState
    private var userID: String?
    private var generation = UUID()
    private var revision = 0
    private var dirty = 0
    private var uploaded = 0
    @Published private(set) var orderCursor: String?
    @Published private(set) var ordersLoading = false
    struct OrderPage: Decodable { let orders: [Order]; let nextCursor: String? }
    private var ready = false
    private var syncTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var accountObserver: AnyCancellable?
    init() {
        let initial = Persistence().load()
        state = initial; guest = initial
        bundledImages = Dictionary(uniqueKeysWithValues: Catalog.bundledProducts.map { ($0.id, $0.imageName) })
        accountObserver = AccountStore.shared.$account.sink { [weak self] account in self?.accountChanged(account?.id) }
    }
    var count: Int { state.cart.reduce(0) { $0 + $1.quantity } }
    var total: Int { state.cart.reduce(0) { result, line in
        guard let product = Catalog.product(line.productID) else { return result }
        return result + (product.cents + (product.isCoffee ? line.options.surcharge(for: product) : 0)) * line.quantity
    } }
    var hasGuestCart: Bool { !guest.cart.isEmpty }
    func importGuestCart() {
        guard userID != nil, ready else { return }
        for line in guest.cart {
            if let index = state.cart.firstIndex(where: { $0.productID == line.productID && $0.options == line.options }) {
                state.cart[index].quantity = min(99, state.cart[index].quantity + line.quantity)
            } else { state.cart.append(line) }
        }
        guest.cart.removeAll(); _ = persistence.save(guest); changed()
    }
    func favorite(_ product: Product) {
        if state.favorites.contains(product.id) { state.favorites.remove(product.id) }
        else { state.favorites.insert(product.id) }
        changed()
    }
    func add(_ product: Product, options: ProductOptions = ProductOptions(), quantity: Int = 1) {
        guard quantity > 0, product.stock != 0, product.active != false else { return }
        if let index = state.cart.firstIndex(where: { $0.productID == product.id && $0.options == options }) {
            state.cart[index].quantity = min(99, state.cart[index].quantity + quantity)
        } else { state.cart.append(CartLine(productID: product.id, options: options, quantity: min(99, quantity))) }
        changed(); showToast("added")
    }
    func change(_ id: UUID, delta: Int) {
        guard let index = state.cart.firstIndex(where: { $0.id == id }) else { return }
        state.cart[index].quantity = min(99, state.cart[index].quantity + delta)
        state.cart.removeAll { $0.quantity <= 0 }; changed()
    }
    func remove(_ id: UUID) { state.cart.removeAll { $0.id == id }; changed() }
    func clear() { state.cart.removeAll(); removeCoupon(); changed() }
    private func changed() {
        couponQuote = nil
        if let offer = selectedMenuOffer, cartCouponCode == offer.code,
           !offer.productIDs.allSatisfy({ id in state.cart.contains { $0.productID == id && $0.quantity > 0 } }) {
            removeCoupon()
        }
        if userID == nil { guest = state; _ = persistence.save(guest) }
        else { dirty += 1; startUpload() }
    }
    private func accountChanged(_ id: String?) {
        guard userID != id else { return }
        generation = UUID(); syncTask?.cancel(); syncTask = nil
        userID = id; revision = 0; dirty = 0; uploaded = 0; ready = false; syncErrorKey = nil
        if id == nil { state = guest; syncing = false }
        else {
            state = SavedState(); syncing = true
            Task { @MainActor in await refreshCloud() }
        }
    }
    @Published private(set) var categories: [RemoteCategory] = []
    @Published private(set) var menuProducts: [Product] = []
    @Published private(set) var menuLoading = false
    @Published private(set) var catalogError: String?
    private var catalogTime = Date.distantPast
    private var catalogLoading = false
    private var catalogTask: Task<Void, Never>?
    private var menuGeneration = UUID()
    private var menuCatalog: [Product] = []
    private var menuCatalogTime = Date.distantPast
    private var menuCatalogTask: Task<[Product], Error>?
    struct ProductPage: Decodable { let products: [Product]; let nextCursor: String? }
    struct Categories: Decodable { let categories: [RemoteCategory] }
    private func remember(_ products: [Product]) {
        var existing = Dictionary(uniqueKeysWithValues: Catalog.products.map { ($0.id, $0) })
        products.forEach { existing[$0.id] = $0 }
        Catalog.products = existing.values.sorted { $0.id < $1.id }; objectWillChange.send()
    }
    func refreshCatalog() async {
        if let task = catalogTask { await task.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.fetchCatalog()
        }
        catalogTask = task
        await task.value
        catalogTask = nil
    }
    func retryCatalog() async {
        if let task = catalogTask { await task.value; return }
        catalogTime = .distantPast
        menuCatalogTime = .distantPast
        await refreshCatalog()
    }
    private func fetchCatalog() async {
        await api.checkPlatform()
        guard !catalogLoading, Date().timeIntervalSince(catalogTime) > 60 else { return }
        catalogLoading = true
        do {
            if !api.supportsPlatform {
                let legacy: CloudCatalog = try await api.get("catalog")
                Catalog.products = legacy.products
                categories = compatibleCategories()
                catalogTime = Date(); catalogError = nil; catalogLoading = false; objectWillChange.send(); return
            }
            let result: ProductPage = try await api.getV2("products", query: [URLQueryItem(name: "limit", value: "24")])
            let home: CloudCatalog = try await api.getV2("home")
            let groups: Categories = try await api.getV2("categories")
            remember(result.products + home.products); try await loadStateProducts(CloudState(favorites: state.favorites, cart: state.cart, revision: revision)); categories = groups.categories; catalogTime = Date(); catalogError = nil
            objectWillChange.send()
        } catch { catalogError = settingsErrorKey(error) }
        catalogLoading = false
    }
    private func compatibleCategories() -> [RemoteCategory] {
        var result: [RemoteCategory] = []
        let values: [Category] = Category.allCases.filter { $0 != .all && $0 != .other }
        for (index, category) in values.enumerated() {
            var names: [String: String] = [:]
            for language in ["tr", "en", "de"] {
                let localized = Copy(language: language)
                names[language] = localized.text(category.key)
            }
            result.append(RemoteCategory(id: category.rawValue, names: names, position: index))
        }
        return result
    }
    private func filterMenuProducts(_ products: [Product], query: String, category: String) -> [Product] {
        let language = UserDefaults.standard.string(forKey: "language") ?? "en"
        let localized = Copy(language: language)
        return products.filter { product in
            guard category.isEmpty || product.categoryID == category else { return false }
            if query.isEmpty { return true }
            let name = product.name(localized)
            if name.localizedStandardContains(query) { return true }
            if product.description(localized).localizedStandardContains(query) { return true }
            let translatedNames = product.names?.values
            return translatedNames?.contains(where: { $0.localizedStandardContains(query) }) ?? false
        }
    }
    // Fetch every API page automatically; the menu never asks the customer to load more.
    private func completeMenuCatalog() async throws -> [Product] {
        if Date().timeIntervalSince(menuCatalogTime) < 60 { return menuCatalog }
        if let task = menuCatalogTask { return try await task.value }
        let task = Task<[Product], Error> { @MainActor in
            var products: [Product] = []
            var seenIDs: Set<String> = []
            var seenCursors: Set<String> = []
            var cursor: String?
            repeat {
                try Task.checkCancellation()
                var query = [URLQueryItem(name: "limit", value: "100")]
                if let value = cursor { query.append(URLQueryItem(name: "cursor", value: value)) }
                let page: ProductPage = try await self.api.getV2("products", query: query)
                for product in page.products {
                    if seenIDs.insert(product.id).inserted { products.append(product) }
                }
                cursor = page.nextCursor
                if let value = cursor, !seenCursors.insert(value).inserted { throw CloudFailure(code: "server") }
            } while cursor != nil
            return products
        }
        menuCatalogTask = task
        do {
            let products = try await task.value
            menuCatalog = products
            menuCatalogTime = Date()
            menuCatalogTask = nil
            remember(products)
            return products
        } catch {
            menuCatalogTask = nil
            throw error
        }
    }
    func loadMenu(query: String, category: String) async {
        let token = UUID()
        menuGeneration = token
        menuLoading = true
        menuProducts = []
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let products: [Product]
            if api.supportsPlatform { products = try await completeMenuCatalog() }
            else { products = Catalog.products }
            guard token == menuGeneration else { return }
            if !Task.isCancelled {
                menuProducts = filterMenuProducts(products, query: normalizedQuery, category: category)
                catalogError = nil
            }
        } catch is CancellationError {
            // A replaced search must not overwrite the next search's state.
        } catch {
            if token == menuGeneration && !Task.isCancelled { catalogError = settingsErrorKey(error) }
        }
        if token == menuGeneration { menuLoading = false }
    }
    private func loadStateProducts(_ cloud: CloudState) async throws {
        guard api.supportsPlatform else { return }
        let ids = Array(Set(cloud.favorites).union(cloud.cart.map(\.productID)))
        for offset in stride(from: 0, to: ids.count, by: 100) {
            let result: CloudCatalog = try await api.sendV2("products/lookup", body: ["ids": Array(ids[offset..<min(ids.count, offset + 100)])])
            remember(result.products)
        }
    }
    func refreshCloud() async {
        guard userID != nil else { return }
        let token = generation
        if let task = syncTask { await task.value }
        do {
            let cloud: CloudState = try await api.get("me/state")
            try await loadStateProducts(cloud)
            let history: OrderPage
            if api.supportsPlatform { history = try await api.getV2("me/orders", query: [URLQueryItem(name: "limit", value: "20")]) }
            else { let old: CloudOrders = try await api.get("me/orders"); history = OrderPage(orders: old.orders, nextCursor: nil) }
            guard generation == token else { return }
            // Preserve edits made locally while the refresh was in flight.
            if dirty == uploaded { state.favorites = cloud.favorites; state.cart = cloud.cart }
            revision = cloud.revision; state.orders = history.orders; orderCursor = history.nextCursor; ready = true; syncErrorKey = nil
        } catch { if generation == token { syncErrorKey = settingsErrorKey(error) } }
        if generation == token { syncing = false; startUpload() }
    }
    func loadMoreOrders() async {
        guard let cursor = orderCursor, !ordersLoading, userID != nil else { return }
        ordersLoading = true; let token = generation
        do {
            let page: OrderPage = try await api.getV2("me/orders", query: [URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "cursor", value: cursor)])
            if token == generation { let ids = Set(state.orders.map(\.id)); state.orders += page.orders.filter { !ids.contains($0.id) }; orderCursor = page.nextCursor }
        } catch { if token == generation { syncErrorKey = settingsErrorKey(error) } }
        ordersLoading = false
    }
    private func startUpload() {
        guard userID != nil, ready, syncTask == nil, dirty > uploaded else { return }
        let token = generation
        syncTask = Task { @MainActor in
            syncing = true
            while generation == token && dirty > uploaded && !Task.isCancelled {
                let version = dirty
                let snapshot = CloudState(favorites: state.favorites, cart: state.cart, revision: revision)
                do {
                    let result: CloudState = try await api.send("me/state", method: "PUT", body: snapshot)
                    guard generation == token else { return }
                    revision = result.revision; uploaded = version; syncErrorKey = nil
                } catch {
                    guard generation == token else { return }
                    syncErrorKey = settingsErrorKey(error)
                    // Keep unsent local changes. Explicit retry re-reads the server revision.
                    break
                }
            }
            if generation == token { syncing = false; syncTask = nil }
        }
    }
    func retrySync() async { catalogTime = .distantPast; await refreshCatalog(); await refreshCloud() }
    func saveDetailedOrder(customer: String, note: String, promotionCode: String? = nil, quotedTotal: Int? = nil, fulfillment: String = "pickup", addressID: UUID? = nil) async throws -> Order {
        guard !placingOrder else { throw CloudFailure(code: "invalid") }
        placingOrder = true
        do {
            let result = try await submitOrder(customer: customer, note: note, promotionCode: promotionCode, quotedTotal: quotedTotal, fulfillment: fulfillment, addressID: addressID)
            placingOrder = false
            return result
        } catch { placingOrder = false; throw error }
    }
    private func submitOrder(customer: String, note: String, promotionCode: String?, quotedTotal: Int?, fulfillment: String, addressID: UUID?) async throws -> Order {
        guard let userID = userID else { throw CloudFailure(code: "loginRequired") }
        guard ready, !state.cart.isEmpty, !customer.isEmpty else { throw CloudFailure(code: "invalid") }
        if let task = syncTask { await task.value }
        let token = generation
        let lines = state.cart
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let metadataParts: [String] = [customer, "\n", note, "\n", promotionCode ?? "", fulfillment,
                                       addressID?.uuidString ?? "", String(quotedTotal ?? total)]
        let metadata: String = metadataParts.joined()
        var fingerprint: Data = try encoder.encode(lines)
        fingerprint.append(Data(metadata.utf8))
        let hash = SHA256.hash(data: fingerprint)
        let digest: String = hash.map { String(format: "%02x", $0) }.joined()
        let key = "cookiecup.pendingOrder." + userID + "." + digest
        let requestKey = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(requestKey.uuidString, forKey: key)
        var request = CloudOrderRequest(requestKey: requestKey, customer: customer, note: note,
                                       expectedTotal: quotedTotal ?? total, lines: lines, revision: revision)
        request.promotionCode = promotionCode; request.fulfillment = api.supportsPlatform ? fulfillment : nil; request.addressID = addressID
        let order: Order = try await api.send("me/orders", body: request)
        guard generation == token else { throw CloudFailure(code: "loginRequired") }
        state.orders.removeAll { $0.id == order.id }; state.orders.insert(order, at: 0)
        // Match the submitted lines only; do not erase additions made during the request.
        let submitted = Set(lines.map(\.id)); state.cart.removeAll { submitted.contains($0.id) }
        uploaded = dirty
        await refreshCloud()
        return order
    }
    func cancelOrder(_ order: Order) async throws {
        let token = generation
        let result: Order = try await api.send("me/orders/" + order.id.uuidString + "/cancel", body: [String: String]())
        guard generation == token else { return }
        if let index = state.orders.firstIndex(where: { $0.id == result.id }) { state.orders[index] = result }
    }
    private func showToast(_ key: String) {
        toastTask?.cancel(); toastKey = key
        toastTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 1_800_000_000) } catch { return }
            toastKey = nil
        }
    }
}
