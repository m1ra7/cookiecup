import SwiftUI

@MainActor
struct CartView: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    @State private var confirmClear = false
    private var hasItems: Bool { !store.state.cart.isEmpty }

    var body: some View {
        Group {
            if hasItems { cartContent }
            else { CafeEmptyState(symbol: "bag", titleKey: "emptyCart") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cafePage()
        .safeAreaInset(edge: .top, spacing: 0) { CafePageHeader(titleKey: "cart") }
        .safeAreaInset(edge: .bottom, spacing: 0) { checkoutFooter }
        .task(id: store.cartContentsKey) {
            if !store.cartCouponCode.isEmpty { await store.applyCartCoupon() }
        }
        .confirmationDialog(copy.text("clearCart"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(copy.text("clearCart"), role: .destructive) { store.clear() }
            Button(copy.text("cancel"), role: .cancel) {}
        }
    }
    private var cartContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                introduction.padding(.bottom, 18)
                VStack(spacing: 12) {
                    ForEach(store.state.cart) { line in
                        if let product = Catalog.product(line.productID) {
                            CompactCartRow(product: product, line: line)
                        }
                    }
                }
                couponSection.padding(.top, 20)
                Label(copy.text("pickupOnly"), systemImage: "bag")
                    .font(.caption).foregroundColor(CafePalette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 22).padding(.horizontal, 4)
            }.padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 26)
        }
    }
    private var introduction: some View {
        HStack {
            Text("\(store.count) " + copy.text("quantity"))
                .font(.subheadline).foregroundColor(CafePalette.secondary)
            Spacer()
            Button { confirmClear = true } label: {
                Label(copy.text("clearCartAction"), systemImage: "trash")
                    .font(.caption).foregroundColor(CafePalette.secondary)
                    .padding(.horizontal, 9).frame(minHeight: 44)
            }.buttonStyle(.plain)
        }.padding(.horizontal, 4)
    }
    private var couponSection: some View {
        CafePanel {
            VStack(alignment: .leading, spacing: 12) {
                Label(copy.text("platform.promotionCode"), systemImage: "ticket")
                    .font(.headline).foregroundColor(CafePalette.cream)
                TextField(copy.text("cartCouponPlaceholder"), text: $store.cartCouponCode)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .submitLabel(.done).onSubmit { Task { await store.applyCartCoupon() } }
                    .padding(13).foregroundColor(CafePalette.cream)
                    .background(CafePalette.header, in: RoundedRectangle(cornerRadius: 13))
                    .accessibilityLabel(copy.text("platform.promotionCode"))
                HStack(spacing: 12) {
                    Button {
                        Task { await store.applyCartCoupon() }
                    } label: {
                        HStack(spacing: 8) {
                            if store.applyingCoupon { ProgressView().tint(CafePalette.surface) }
                            Text(copy.text("platform.apply"))
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(CafePrimaryButton())
                        .disabled(store.applyingCoupon || store.cartCouponCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !store.cartCouponCode.isEmpty {
                        Button { store.removeCoupon() } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }.buttonStyle(.plain).foregroundColor(CafePalette.secondary)
                            .accessibilityLabel(copy.text("cartRemoveCoupon"))
                    }
                }
                if let quote = store.couponQuote {
                    HStack {
                        Label(copy.text("cartCouponApplied"), systemImage: "checkmark.circle.fill")
                        Spacer(minLength: 4)
                        Text("−" + copy.money(quote.discountCents))
                    }.font(.caption).foregroundColor(CafePalette.cream)
                }
                if let error = store.couponErrorKey {
                    Text(copy.text(error)).font(.caption).foregroundColor(CafePalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private var checkoutFooter: some View {
        if hasItems {
            VStack(spacing: 15) {
                if let quote = store.couponQuote {
                    HStack {
                        Text(copy.text("platform.discount"))
                        Spacer()
                        Text("−" + copy.money(quote.discountCents))
                    }.font(.caption).foregroundColor(CafePalette.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.text("total")).font(.subheadline).foregroundColor(CafePalette.secondary)
                        Text(copy.text("payAtCafe")).font(.caption2).foregroundColor(CafePalette.secondary)
                    }
                    Spacer()
                    Text(copy.money(store.couponQuote?.totalCents ?? store.total)).font(CafeTypography.script(29)).foregroundColor(CafePalette.cream)
                }
                NavigationLink(destination: CheckoutView()) {
                    Text(copy.text("checkout"))
                }.buttonStyle(CafePrimaryButton())
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 12)
            .background(CafePalette.surface)
            .overlay(alignment: .top) {
                Rectangle().fill(CafePalette.cream.opacity(0.12)).frame(height: 1)
            }
        }
    }
}

@MainActor
private struct CompactCartRow: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    let product: Product
    let line: CartLine
    private var lineTotal: Int { (product.cents + (product.isCoffee ? line.options.surcharge(for: product) : 0)) * line.quantity }
    private var optionsText: String {
        [line.options.size, line.options.milk, line.options.sugar, line.options.extra]
            .map { copy.text("option." + $0) }.joined(separator: " · ")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                photo
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 3) {
                        Text(product.name(copy)).font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        removeButton
                    }
                    if product.isCoffee {
                        Text(optionsText).font(.caption).foregroundColor(CafePalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack {
                quantityControls
                Spacer(minLength: 8)
                Text(copy.money(lineTotal)).font(.system(size: 18, weight: .semibold))
                    .foregroundColor(CafePalette.cream)
            }
        }
        .padding(15)
        .background(CafePalette.surface, in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(CafePalette.cream.opacity(0.07), lineWidth: 1))
    }
    private var photo: some View {
        CachedProductImage(imageName: product.imageName, imagePath: product.imagePath).scaledToFit().padding(8)
            .frame(width: 72, height: 78)
            .background(CafePalette.header.opacity(0.65), in: RoundedRectangle(cornerRadius: 17))
            .accessibilityHidden(true)
    }
    private var removeButton: some View {
        Button { store.remove(line.id) } label: {
            Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                .foregroundColor(CafePalette.secondary).frame(width: 44, height: 44)
        }.buttonStyle(.plain).accessibilityLabel(copy.text("remove"))
    }
    private var quantityControls: some View {
        HStack(spacing: 0) {
            Button { store.change(line.id, delta: -1) } label: {
                Image(systemName: "minus").font(.system(size: 13)).frame(width: 44, height: 44)
            }.accessibilityLabel(copy.text("decrease"))
            Text("\(line.quantity)").font(.subheadline.weight(.semibold)).monospacedDigit().frame(width: 25)
            Button { store.change(line.id, delta: 1) } label: {
                Image(systemName: "plus").font(.system(size: 13)).frame(width: 44, height: 44)
            }.accessibilityLabel(copy.text("increase"))
        }.foregroundColor(CafePalette.cream).buttonStyle(.plain)
            .background(CafePalette.header.opacity(0.6), in: Capsule())
    }
}
