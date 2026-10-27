import SwiftUI
import CoreText

// The font is bundled and registered locally, so no network is needed at runtime.
enum CafeTypography {
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "Pacifico-Regular", withExtension: "ttf", subdirectory: "Fonts") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
    static var homeSectionTitle: Font { script(26) }
    static var productTitle: Font { script(20, relativeTo: .headline) }

    static func script(_ size: CGFloat, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom("Pacifico-Regular", size: size, relativeTo: style)
    }
}

private enum HomePalette {
    static let background = Color(red: 0.25, green: 0.15, blue: 0.13)
    static let header = Color(red: 0.31, green: 0.20, blue: 0.18)
    static let card = Color(red: 0.18, green: 0.09, blue: 0.035)
    static let secondary = Color(red: 0.79, green: 0.73, blue: 0.69)
}

@MainActor
struct HomeView: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    @State private var showInbox = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.homeLayout.sections.filter { $0.enabled }) { section in
                    homeSection(section)
                }
            }
            .padding(.bottom, 22)
        }
        .task { await store.refreshHomeLayout() }
        .refreshable { await store.refreshHomeLayout(force: true) }
        .onChange(of: scenePhase) { value in
            if value == .active { Task { await store.refreshHomeLayout(force: true) } }
        }
        .background(HomePalette.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(HomePalette.card, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .sheet(isPresented: $showInbox) { NavigationStack { NotificationsView().toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(copy.text("settingsClose")) { showInbox = false } } } } }
    }

    private var header: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Spacer(minLength: 0)
            Text(copy.text("home")).font(CafeTypography.script(35)).foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.65)
            Spacer(minLength: 0)
            Button { showInbox = true } label: { Image(systemName: "bell").foregroundColor(Theme.cream).frame(width: 44, height: 44) }.accessibilityLabel(copy.text("platform.notifications"))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(HomePalette.header.ignoresSafeArea(edges: .top))
    }

    @ViewBuilder private func homeSection(_ section: HomeSection) -> some View {
        switch section.kind {
        case "hero": HomeCoffeeHero(quote: section.heading(copy))
        case "deals": menuDeals(section)
        case "products": productSection(section)
        default: EmptyView()
        }
    }

    @ViewBuilder private func sectionHeading(_ section: HomeSection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !section.heading(copy).isEmpty {
                Text(section.heading(copy))
                    .font(CafeTypography.homeSectionTitle)
                    .foregroundColor(CafePalette.cream).fixedSize(horizontal: false, vertical: true)
            }
            if !section.subtitle(copy).isEmpty {
                Text(section.subtitle(copy)).font(.caption).foregroundColor(CafePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.horizontal, 20)
    }

    @ViewBuilder private func productSection(_ section: HomeSection) -> some View {
        let products = section.productIDs.compactMap { Catalog.product($0) }.filter { $0.active != false }
        if !products.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeading(section)
                if section.layout == "list" {
                    VStack(spacing: 14) {
                        ForEach(products) { product in HomeRecommendationCard(product: product) }
                    }.padding(.horizontal, 24)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 22) {
                            ForEach(products) { product in ProductCard(product: product) }
                        }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 16)
                    }
                }
            }.padding(.top, 8).padding(.bottom, 18)
        }
    }

    @ViewBuilder private func menuDeals(_ section: HomeSection) -> some View {
        let offers = section.offerIDs.compactMap { id in store.menuOffers.first { $0.id == id } }.filter { $0.available }
        let legacyOffers = store.homeLayout.version == 0 ? store.menuOffers.filter { $0.available } : offers
        if !legacyOffers.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                sectionHeading(section)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(legacyOffers) { offer in HomeMenuOfferCard(offer: offer) }
                    }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 10)
                }
                Text(copy.text("homeMenuCheckout"))
                    .font(.caption2).foregroundColor(CafePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 20)
            }.padding(.top, 6).padding(.bottom, 18)
        }
    }

}

@MainActor
private struct HomeCoffeeHero: View {
    let quote: String

    var body: some View {
        VStack(spacing: 8) {
            Text(quote)
                .font(CafeTypography.script(20, relativeTo: .headline))
                .foregroundColor(HomePalette.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
            Image("caffe_makinesi")
                .resizable().scaledToFit()
                .frame(height: 180)
                .frame(maxWidth: 300)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

@MainActor
private struct HomeRecommendationCard: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    let product: Product

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: product) {
                productContent
            }.buttonStyle(.plain)
            HStack(spacing: 12) {
                Text(copy.money(product.cents))
                    .font(.system(size: 17, weight: .semibold)).foregroundColor(CafePalette.cream)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { store.add(product) }
                } label: {
                    Label(copy.text("add"), systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundColor(CafePalette.surface)
                        .background(CafePalette.cream, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26)
            .stroke(CafePalette.cream.opacity(0.16), lineWidth: 1))
    }

    private var productContent: some View {
        HStack(alignment: .center, spacing: 14) {
            CachedProductImage(imageName: product.imageName, imagePath: product.imagePath).scaledToFit()
                .frame(width: 90, height: 100)
                .background(CafePalette.cream.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name(copy))
                    .font(CafeTypography.productTitle)
                    .foregroundColor(CafePalette.cream)
                Text(product.description(copy))
                    .font(.system(size: 12)).foregroundColor(CafePalette.secondary)
                    .lineLimit(ProductCardLayout.descriptionLineLimit(for: product, copy: copy) == nil ? nil : 3).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.contentShape(Rectangle())
    }

    private var cardBackground: LinearGradient {
        LinearGradient(colors: [HomePalette.header, HomePalette.card],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

@MainActor
private struct HomeMenuOfferCard: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let offer: MenuOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            offerHeader.frame(height: 20)
            products
            Text(offer.name(copy))
                .font(CafeTypography.script(17, relativeTo: .headline))
                .foregroundColor(CafePalette.cream)
                .lineLimit(2).minimumScaleFactor(0.8)
                .frame(height: 42, alignment: .topLeading)
            Spacer(minLength: 0)
            purchaseRow
        }
        .padding(10)
        .frame(width: 196, height: 212, alignment: .topLeading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(CafePalette.cream.opacity(0.12), lineWidth: 1))
    }

    private var offerHeader: some View {
        HStack(spacing: 6) {
            Label(copy.text("menu"), systemImage: "ticket")
                .font(.caption2).foregroundColor(CafePalette.secondary)
            Spacer(minLength: 4)
            Text("−" + copy.money(offer.discountCents))
                .font(.caption2.weight(.semibold)).foregroundColor(CafePalette.cream)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(CafePalette.cream.opacity(0.09), in: Capsule())
                .accessibilityLabel(copy.text("homeMenuSaving") + " " + copy.money(offer.discountCents))
        }
    }

    private var products: some View {
        HStack(spacing: 5) {
            if let first = offer.products.first { photo(first) }
            if let last = offer.products.last { photo(last) }
        }
        .padding(.vertical, 4)
        .background(CafePalette.cream.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func photo(_ product: Product) -> some View {
        NavigationLink(value: product) {
            CachedProductImage(imageName: product.imageName, imagePath: product.imagePath)
                .scaledToFit().frame(height: 52).frame(maxWidth: .infinity)
                .padding(.horizontal, 5)
        }.buttonStyle(.plain).accessibilityLabel(product.name(copy))
    }

    private var purchaseRow: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(copy.money(offer.subtotal)).font(.caption2).strikethrough()
                    .foregroundColor(CafePalette.secondary)
                Text(copy.money(offer.total)).font(.system(size: 20, weight: .semibold))
                    .foregroundColor(CafePalette.cream).monospacedDigit()
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { store.addMenu(offer) }
            } label: {
                Image(systemName: "plus").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
                    .foregroundColor(CafePalette.surface).background(CafePalette.cream, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(copy.text("homeAddMenu"))
        }
    }

    private var cardBackground: LinearGradient {
        LinearGradient(colors: [HomePalette.header, HomePalette.card],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
