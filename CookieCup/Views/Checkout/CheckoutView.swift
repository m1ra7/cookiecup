import SwiftUI

@MainActor
struct CheckoutView: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    @Environment(\.dismiss) private var dismiss
    @State private var promotionCode = ""
    @State private var quote: CheckoutQuote?
    @State private var quoting = false
    @State private var deliveryEnabled = false
    @State private var fulfillment = "pickup"
    @State private var addressID: UUID?
    struct CheckoutQuote: Decodable { let subtotalCents: Int; let discountCents: Int; let totalCents: Int }
    struct QuoteRequest: Encodable { let lines: [CartLine]; let promotionCode: String?; let fulfillment: String; let addressID: UUID? }
    @State private var customer = ""
    @State private var note = ""
    @State private var busy = false
    @State private var completed = false
    @State private var placedOrder: Order?
    @State private var detailOrder: Order?
    @State private var saveFailed = false
    @State private var errorKey = "orderSaveFailed"
    private var canSubmit: Bool {
        !busy && !quoting && !store.state.cart.isEmpty && !customer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var body: some View {
        Group {
            if completed { successContent }
            else { checkoutContent }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CafePalette.background.ignoresSafeArea()).foregroundColor(.white)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(CafePalette.header, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .principal) {
            Text(copy.text("checkout")).font(CafeTypography.script(26)).foregroundColor(.white)
        } }
        .safeAreaInset(edge: .bottom) { submitFooter }
        .interactiveDismissDisabled(busy)
        .navigationBarBackButtonHidden(busy)
        .tint(CafePalette.cream)
        .onAppear {
            if customer.isEmpty { customer = AccountStore.shared.account?.name ?? "" }
            if promotionCode.isEmpty { promotionCode = store.cartCouponCode }
        }
        .task {
            guard APIClient.shared.supportsPlatform else { return }
            do { let capabilities: PlatformCapabilities = try await APIClient.shared.getV2("capabilities"); deliveryEnabled = capabilities.deliveryEnabled }
            catch { errorKey = settingsErrorKey(error); saveFailed = true }
            addressID = AccountStore.shared.account?.defaultAddressID
            if !promotionCode.isEmpty {
                quoting = true
                do { quote = try await fetchQuote() }
                catch { errorKey = settingsErrorKey(error); saveFailed = true }
                quoting = false
            }
        }
        .onChange(of: promotionCode) { _ in quote = nil }
        .onChange(of: fulfillment) { _ in quote = nil }
        .onChange(of: addressID) { _ in quote = nil }
        .onChange(of: store.total) { _ in quote = nil }
        .sheet(item: $detailOrder) { order in OrderDetailView(order: order) }
        .alert(copy.text(errorKey), isPresented: $saveFailed) {
            Button(copy.text("settingsClose"), role: .cancel) { }
        }
    }
    private var checkoutContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                CafePanel {
                    VStack(alignment: .leading, spacing: 15) {
                        if deliveryEnabled {
                            Picker(copy.text("pickup"), selection: $fulfillment) {
                                Text(copy.text("pickup")).tag("pickup")
                                Text(copy.text("platform.delivery")).tag("delivery")
                            }.pickerStyle(.segmented)
                            if fulfillment == "delivery" {
                                Picker(copy.text("settings.address"), selection: $addressID) {
                                    Text("—").tag(nil as UUID?)
                                    ForEach(AccountStore.shared.account?.addresses ?? []) { address in Text(address.label + " · " + address.street).tag(Optional(address.id)) }
                                }
                            }
                        }
                        Text(copy.text("pickup")).font(CafeTypography.script(25)).foregroundColor(CafePalette.cream)
                        TextField("", text: $customer, prompt: Text(copy.text("yourName")).foregroundColor(CafePalette.secondary))
                            .textContentType(.name).padding(14)
                            .background(CafePalette.header, in: RoundedRectangle(cornerRadius: 14))
                        TextField("", text: $note, prompt: Text(copy.text("orderNote")).foregroundColor(CafePalette.secondary), axis: .vertical)
                            .lineLimit(3...5).padding(14)
                            .background(CafePalette.header, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
                if APIClient.shared.supportsPlatform { couponSection }
                CafePanel {
                    VStack(alignment: .leading, spacing: 15) {
                        Text(copy.text("summary")).font(CafeTypography.script(25)).foregroundColor(CafePalette.cream)
                        HStack { Text(copy.text("quantity")); Spacer(); Text("\(store.count)") }
                        if let quote = quote, quote.discountCents > 0 {
                            HStack { Text(copy.text("platform.discount")); Spacer(); Text("−" + copy.money(quote.discountCents)) }
                        }
                        HStack { Text(copy.text("total")); Spacer(); Text(copy.money(quote?.totalCents ?? store.total)).bold() }
                        Label(copy.text("payAtCafe"), systemImage: "creditcard")
                            .font(.subheadline).foregroundColor(CafePalette.secondary)
                    }
                }
                Text(copy.text("demoNotice")).font(.footnote).foregroundColor(CafePalette.secondary)
                    .padding(.horizontal, 5)
            }.padding(20)
        }.scrollDismissesKeyboard(.interactively)
    }
    private var couponSection: some View {
        CafePanel {
            VStack(alignment: .leading, spacing: 12) {
                SettingsInput(key: "platform.promotionCode", text: $promotionCode)
                Button(copy.text("platform.apply")) {
                    quoting = true
                    Task { @MainActor in
                        do { quote = try await fetchQuote() }
                        catch { quote = nil; errorKey = settingsErrorKey(error); saveFailed = true }
                        quoting = false
                    }
                }.buttonStyle(CafePrimaryButton()).disabled(quoting || busy)
                SettingsNote(key: "platform.verifyQuote")
            }
        }
    }
    private func fetchQuote() async throws -> CheckoutQuote {
        let code = promotionCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return try await APIClient.shared.sendV2("me/quote", body: QuoteRequest(lines: store.state.cart, promotionCode: code.isEmpty ? nil : code, fulfillment: fulfillment, addressID: addressID))
    }
    @ViewBuilder private var submitFooter: some View {
        if !completed {
            Button {
                guard canSubmit else { return }
                busy = true
                Task { @MainActor in
                    do {
                        // Revalidate before submission. Never silently accept a changed total.
                        let confirmed: CheckoutQuote
                        if APIClient.shared.supportsPlatform {
                            confirmed = try await fetchQuote()
                        } else {
                            confirmed = CheckoutQuote(subtotalCents: store.total, discountCents: 0, totalCents: store.total)
                        }
                        guard confirmed.totalCents == (quote?.totalCents ?? store.total) else {
                            quote = confirmed; throw CloudFailure(code: "pricesChanged")
                        }
                        let order = try await store.saveDetailedOrder(customer: customer.trimmingCharacters(in: .whitespacesAndNewlines), note: note, promotionCode: promotionCode.isEmpty ? nil : promotionCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines), quotedTotal: confirmed.totalCents, fulfillment: fulfillment, addressID: addressID)
                        placedOrder = order; completed = true
                    } catch {
                        errorKey = settingsErrorKey(error); saveFailed = true
                        if (error as? CloudFailure)?.code == "pricesChanged" { await store.refreshCatalog() }
                    }
                    busy = false
                }
            } label: {
                HStack {
                    Text(copy.text("saveDemoOrder"))
                    if busy { ProgressView().tint(CafePalette.surface) }
                }
            }
            .buttonStyle(CafePrimaryButton()).disabled(!canSubmit).opacity(canSubmit ? 1 : 0.5)
            .padding(20).background(CafePalette.header)
        }
    }
    private var successContent: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 76)).foregroundColor(CafePalette.cream)
            Button { detailOrder = placedOrder } label: {
                VStack(spacing: 8) {
                    Text(copy.text("orderSaved")).font(CafeTypography.script(30))
                    Label(copy.text("viewOrder"), systemImage: "chevron.right").font(.subheadline)
                }.multilineTextAlignment(.center)
            }.buttonStyle(.plain).foregroundColor(CafePalette.cream)
            Text(copy.text("demoNotice")).foregroundColor(CafePalette.secondary).multilineTextAlignment(.center)
            Button(copy.text("backHome")) { dismiss(); store.selectedTab = 0 }
                .buttonStyle(CafePrimaryButton())
        }.padding(30)
    }
}

