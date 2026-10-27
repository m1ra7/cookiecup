import SwiftUI

private enum MenuPalette {
    static let background = Color(red: 0.25, green: 0.15, blue: 0.13)
    static let header = Color(red: 0.31, green: 0.20, blue: 0.18)
    static let surface = Color(red: 0.18, green: 0.09, blue: 0.035)
    static let cream = Color(red: 0.94, green: 0.88, blue: 0.79)
    static let secondary = Color(red: 0.79, green: 0.73, blue: 0.69)
}

@MainActor
struct MenuView: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    @State private var search = ""
    @State private var categoryID = ""
    private var results: [Product] { store.menuProducts }
    private var sections: [RemoteMenuSection] {
        store.categories.compactMap { group in
            let products = results.filter { $0.categoryID == group.id }
            return products.isEmpty ? nil : RemoteMenuSection(category: group, products: products)
        }
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    introduction.id("menuTop")
                    if results.isEmpty {
                        if store.menuLoading { ProgressView().frame(maxWidth: .infinity).padding(40) } else { emptyResults }
                    } else {
                        productSections
                        if store.menuLoading { ProgressView().frame(maxWidth: .infinity) }
                    }
                    if store.catalogError != nil {
                        SettingsError(key: store.catalogError).padding(.horizontal, 24)
                        Button(copy.text("platform.retry")) {
                            Task { @MainActor in
                                await store.retryCatalog()
                                await store.loadMenu(query: search, category: categoryID)
                            }
                        }.buttonStyle(CafePrimaryButton()).padding(.horizontal, 24)
                    }
                }.padding(.top, 20).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: categoryID) { _ in proxy.scrollTo("menuTop", anchor: .top) }
            .onChange(of: search) { _ in proxy.scrollTo("menuTop", anchor: .top) }
            .onChange(of: copy.language) { _ in proxy.scrollTo("menuTop", anchor: .top) }
        }
        .background(MenuPalette.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { controls }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(MenuPalette.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .task(id: search + ":" + categoryID + ":" + copy.language) {
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            await store.refreshCatalog()
            guard !Task.isCancelled else { return }
            await store.loadMenu(query: search.trimmingCharacters(in: .whitespacesAndNewlines), category: categoryID)
        }
        .compatibleFeedback(.selection, trigger: categoryID)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            MenuHeader()
            MenuSearchField(text: $search).padding(.horizontal, 20)
            categoryPicker
        }
        .padding(.top, 8).padding(.bottom, 14)
        .background(MenuPalette.header.ignoresSafeArea(edges: .top))
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                categoryButton(id: "", title: copy.text("category.all"))
                ForEach(store.categories) { item in categoryButton(id: item.id, title: item.name(copy)) }
            }.padding(.horizontal, 20)
        }
    }

    private func categoryButton(id: String, title: String) -> some View {
        Button { categoryID = id } label: {
            Text(title).font(.system(size: 13, weight: categoryID == id ? .semibold : .regular))
                .foregroundColor(categoryID == id ? MenuPalette.surface : MenuPalette.cream)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(categoryID == id ? MenuPalette.cream : MenuPalette.surface, in: Capsule())
        }.buttonStyle(.plain)
    }
    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(copy.text("menuSubtitle"))
                .font(CafeTypography.homeSectionTitle)
                .foregroundColor(MenuPalette.cream)
            HStack(spacing: 8) {
                Rectangle().fill(MenuPalette.cream.opacity(0.45)).frame(width: 24, height: 1)
                Text("\(results.count) " + copy.text("menuItems"))
                    .font(.caption).foregroundColor(MenuPalette.secondary)
            }
        }.padding(.horizontal, 24)
    }

    private var productSections: some View {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(sections) { section in
                MenuProductShelf(category: Category(rawValue: section.category.id) ?? .other, products: section.products, title: section.category.name(copy))
            }
        }
    }

    private var emptyResults: some View {
        VStack(spacing: 15) {
            Image(systemName: "magnifyingglass").font(.system(size: 32, weight: .light))
                .foregroundColor(MenuPalette.cream)
            Text(copy.text("noProducts")).font(.headline).foregroundColor(.white)
            Text(copy.text("menuEmptyHint")).font(.subheadline)
                .foregroundColor(MenuPalette.secondary).multilineTextAlignment(.center)
            Button(copy.text("menuReset")) { search = ""; categoryID = "" }
                .font(.subheadline.bold()).foregroundColor(MenuPalette.surface)
                .padding(.horizontal, 20).padding(.vertical, 13)
                .background(MenuPalette.cream, in: Capsule())
        }
        .padding(26).frame(maxWidth: .infinity)
        .background(MenuPalette.surface, in: RoundedRectangle(cornerRadius: 25))
        .padding(.horizontal, 24)
    }
}

@MainActor
private struct MenuHeader: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    var body: some View {
        HStack {
            Color.clear.frame(width: 44, height: 44)
            Spacer(minLength: 8)
            Text(copy.text("menu")).font(CafeTypography.script(35))
                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Button { store.selectedTab = 3 } label: { cartIcon }
                .buttonStyle(.plain).accessibilityLabel(copy.text("cart") + ", \(store.count)")
        }.padding(.horizontal, 20)
    }
    private var cartIcon: some View {
        Image(systemName: "bag").font(.system(size: 22, weight: .regular))
            .foregroundColor(MenuPalette.cream).frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                if store.count > 0 {
                    Text(store.count > 99 ? "99+" : "\(store.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(MenuPalette.surface).padding(4)
                        .background(MenuPalette.cream, in: Capsule())
                }
            }
    }
}

@MainActor
private struct MenuSearchField: View {
    @Environment(\.copy) private var copy
    @Binding var text: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").foregroundColor(MenuPalette.secondary)
            TextField("", text: $text, prompt: Text(copy.text("search")).foregroundColor(MenuPalette.secondary))
                .font(.subheadline).foregroundColor(.white).tint(MenuPalette.cream)
                .focused($focused).submitLabel(.search)
                .autocorrectionDisabled().textInputAutocapitalization(.never)
                .onSubmit { focused = false }
                .accessibilityLabel(copy.text("search"))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(MenuPalette.secondary)
                        .frame(width: 32, height: 32)
                }.accessibilityLabel(copy.text("menuClearSearch"))
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 50)
        .background(MenuPalette.surface, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(MenuPalette.cream.opacity(0.12), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

@MainActor
private struct MenuCategoryChip: View {
    @Environment(\.copy) private var copy
    let category: Category
    let selected: Bool
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: category.symbol).font(.system(size: 12))
            Text(copy.text(category.key)).font(.system(size: 13, weight: selected ? .semibold : .regular))
        }
        .foregroundColor(selected ? MenuPalette.surface : MenuPalette.cream)
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(selected ? MenuPalette.cream : MenuPalette.surface.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(MenuPalette.cream.opacity(selected ? 0 : 0.15), lineWidth: 1))
    }
}

@MainActor
private struct MenuProductShelf: View {
    @Environment(\.copy) private var copy
    let category: Category
    let products: [Product]
    let title: String

    private var shelfHeight: CGFloat {
        let maximumHeight = products.map { ProductCardLayout.metrics(for: $0, copy: copy).height }.max() ?? 0
        return maximumHeight + 20
    }
    private var shelfIdentity: String {
        return category.rawValue + ":" + copy.language + ":" + products.map { $0.id }.joined(separator: ",")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(CafeTypography.homeSectionTitle)
                    .foregroundColor(.white)
                Spacer(minLength: 0)
                Text("\(products.count)").font(.caption.weight(.medium))
                    .foregroundColor(MenuPalette.secondary)
            }.padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 22) {
                    ForEach(products) { ProductCard(product: $0) }
                }.padding(.horizontal, 24).padding(.vertical, 10)
            }
            // Explicit shelf height keeps nested lazy layout stable.
            .frame(height: shelfHeight, alignment: .top)
            // Filtered rows must start at their first item, not an old horizontal offset.
            .id(shelfIdentity)
        }
    }
}

private struct MenuCategoryProducts: Identifiable {
    let category: Category
    let products: [Product]
    var id: Category { category }
}

private struct RemoteMenuSection: Identifiable {
    let category: RemoteCategory
    let products: [Product]
    var id: String { category.id }
}
