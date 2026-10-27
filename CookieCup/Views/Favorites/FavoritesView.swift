import SwiftUI

@MainActor
struct FavoritesView: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    private var products: [Product] {
        Catalog.products.filter { store.state.favorites.contains($0.id) }
    }
    private var categories: [Category] {
        Category.allCases.filter { item in products.contains { $0.category == item } }
    }
    var body: some View {
        Group {
            if products.isEmpty {
                CafeEmptyState(symbol: "heart", titleKey: "noFavorites")
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        introduction
                        ForEach(categories) { category in
                            FavoriteShelf(category: category, products: products.filter { $0.category == category })
                        }
                    }.padding(.vertical, 22)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .cafePage()
        .safeAreaInset(edge: .top, spacing: 0) { CafePageHeader(titleKey: "favorites") }
    }
    private var introduction: some View {
        HStack(spacing: 13) {
            Image(systemName: "heart.fill").foregroundColor(CafePalette.cream)
                .frame(width: 42, height: 42).background(CafePalette.cream.opacity(0.07), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.text("favoritesSubtitle")).font(CafeTypography.script(24))
                    .foregroundColor(CafePalette.cream)
                Text("\(products.count) " + copy.text("favoritesSaved"))
                    .font(.caption).foregroundColor(CafePalette.secondary)
            }
        }.padding(.horizontal, 24)
    }
}

@MainActor
private struct FavoriteShelf: View {
    @Environment(\.copy) private var copy
    let category: Category
    let products: [Product]
    private var height: CGFloat {
        guard let product = products.first else { return 0 }
        return ProductCardLayout.metrics(for: product, copy: copy).height + 20
    }
    private var identity: String {
        category.rawValue + copy.language + products.map { $0.id }.joined(separator: ",")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.text(category.key)).font(CafeTypography.script(26))
                .foregroundColor(.white).padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(products) { ProductCard(product: $0) }
                }.padding(.horizontal, 24).padding(.vertical, 10)
            }.frame(height: height, alignment: .top).id(identity)
        }
    }
}
