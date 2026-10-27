import Foundation

enum Category: String, Codable, CaseIterable, Identifiable {
    case all, coffee, coldCoffee, cookies, desserts, tea, coldDrinks, snacks, other
    var id: String { rawValue }
    var key: String { "category." + rawValue }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .coffee: return "cup.and.saucer.fill"
        case .coldCoffee: return "snowflake"
        case .cookies: return "circle.dotted.circle.fill"
        case .desserts: return "birthday.cake.fill"
        case .tea: return "leaf.fill"
        case .coldDrinks: return "waterbottle.fill"
        case .snacks: return "fork.knife"
        case .other: return "square.grid.2x2"
        }
    }
}
struct Product: Identifiable, Codable, Hashable {
    let id: String
    let imageName: String
    let categoryID: String
    let cents: Int
    var names: [String: String]? = nil
    var descriptions: [String: String]? = nil
    var ingredients: [String: String]? = nil
    var recipes: [String: String]? = nil
    var allergens: [String: String]? = nil
    var calories: Int? = nil
    var isEstimate: Bool? = nil
    var imagePath: String? = nil
    var stock: Int? = nil
    var active: Bool? = nil
    var customizable: Bool? = nil
    var version: Int? = nil
    var optionSurcharges: [String: Int]? = nil
    var category: Category { Category(rawValue: categoryID) ?? .other }
    var drinkDetails: DrinkDetails? { Catalog.drinkDetails[id] }
    var isCoffee: Bool { customizable ?? (category == .coffee || category == .coldCoffee) }
    var nameKey: String { "product." + id }
    var descriptionKey: String { "description." + id }
    func name(_ copy: Copy) -> String { names?[copy.language] ?? names?["en"] ?? copy.text(nameKey) }
    func description(_ copy: Copy) -> String { descriptions?[copy.language] ?? descriptions?["en"] ?? copy.text(descriptionKey) }
    init(id: String, imageName: String, category: Category, cents: Int) {
        self.id = id; self.imageName = imageName; self.categoryID = category.rawValue; self.cents = cents
    }
    enum CodingKeys: String, CodingKey {
        case id, imageName, cents, names, descriptions, ingredients, recipes, allergens, calories, isEstimate, imagePath, stock, active, customizable, version, optionSurcharges
        case categoryID = "category"
    }
    static func == (lhs: Product, rhs: Product) -> Bool { lhs.id == rhs.id && lhs.version == rhs.version && lhs.cents == rhs.cents && lhs.imagePath == rhs.imagePath }
    func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(version); hasher.combine(cents); hasher.combine(imagePath) }
}
struct RemoteCategory: Decodable, Identifiable {
    let id: String
    let names: [String: String]
    let position: Int
    func name(_ copy: Copy) -> String { names[copy.language] ?? names["en"] ?? id }
}
struct ProductOptions: Codable, Hashable {
    var size = "regular"
    var milk = "whole"
    var sugar = "none"
    var extra = "none"
    func surcharge(for product: Product) -> Int {
        guard let prices = product.optionSurcharges, !prices.isEmpty else { return surcharge }
        return [("size", size), ("milk", milk), ("sugar", sugar), ("extra", extra)].reduce(0) { $0 + (prices[$1.0 + "." + $1.1] ?? 0) }
    }
    var surcharge: Int { (size == "large" ? 80 : 0) + (milk == "oat" ? 50 : 0) + (extra == "shot" ? 70 : extra == "vanilla" ? 50 : 0) }
}
struct CartLine: Identifiable, Codable {
    var id = UUID()
    let productID: String
    let options: ProductOptions
    var quantity: Int
}
struct SavedState: Codable {
    var favorites: Set<String> = []
    var cart: [CartLine] = []
    var orders: [Order] = []
}
struct Order: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let totalCents: Int
    let itemCount: Int
    let customer: String
    let note: String
    // Optional for decoding orders saved before product snapshots existed.
    var items: [OrderItem]? = nil
    var status: String? = nil
    var discountCents: Int? = nil
    var fulfillment: String? = nil
    var version: Int? = nil
}

// Display-only metadata: adding drinks does not change Codable persistence.
struct DrinkDetails {
    let calories: Int
    let isEstimate: Bool
    let containsAlcohol: Bool
    let sourceURL: String
}

struct OrderItem: Identifiable, Codable {
    var id = UUID()
    let productID: String
    let imageName: String
    let names: [String: String]
    let options: ProductOptions
    let isCoffee: Bool
    let quantity: Int
    let unitCents: Int
    var imagePath: String? = nil
    var totalCents: Int { unitCents * quantity }
}

struct MenuOffer: Decodable, Identifiable {
    let id: String
    let code: String
    let names: [String: String]
    let productIDs: [String]
    let discountCents: Int
    let minSpend: Int
    let endsAt: Date
    func name(_ copy: Copy) -> String { names[copy.language] ?? names["en"] ?? code }
    var products: [Product] { productIDs.compactMap { Catalog.product($0) } }
    var subtotal: Int { products.reduce(0) { $0 + $1.cents } }
    var total: Int { max(0, subtotal - discountCents) }
    var available: Bool {
        productIDs.count == 2 && products.count == 2 && subtotal >= minSpend && endsAt > Date()
            && products.allSatisfy { $0.active != false && $0.stock != 0 }
    }
}

struct CartQuote: Decodable {
    let subtotalCents: Int
    let discountCents: Int
    let totalCents: Int
}

struct HomeSection: Codable, Identifiable {
    let id: String
    let kind: String
    let enabled: Bool
    let titles: [String: String]
    let subtitles: [String: String]
    let productIDs: [String]
    let offerIDs: [String]
    let layout: String
    func heading(_ copy: Copy) -> String { titles[copy.language] ?? titles["en"] ?? "" }
    func subtitle(_ copy: Copy) -> String { subtitles[copy.language] ?? subtitles["en"] ?? "" }
}
struct HomeLayout: Codable {
    let version: Int
    let sections: [HomeSection]
    static var starter: HomeLayout {
        let data = Data(#"{"version": 0, "sections": [{"id": "hero", "kind": "hero", "enabled": true, "titles": {"tr": "Bugünkü güzel ruh halimin\nsırrı kahve", "en": "My good mood today is\npowered by coffee", "de": "Meine gute Laune heute\nkommt vom Kaffee"}, "subtitles": {"tr": "", "en": "", "de": ""}, "productIDs": [], "offerIDs": [], "layout": "carousel"}, {"id": "deals", "kind": "deals", "enabled": true, "titles": {"tr": "Avantajlı Menüler", "en": "Menu Deals", "de": "Menüangebote"}, "subtitles": {"tr": "Birlikte daha lezzetli, birlikte daha avantajlı.", "en": "Your favourite pairings, for a little less.", "de": "Lieblingskombinationen zum Vorteilspreis."}, "productIDs": [], "offerIDs": [], "layout": "carousel"}, {"id": "popular", "kind": "products", "enabled": true, "titles": {"tr": "En Sevilenler", "en": "Most Popular", "de": "Am beliebtesten"}, "subtitles": {"tr": "", "en": "", "de": ""}, "productIDs": ["chocolateChip", "butter", "doubleChocolate", "brownie", "almond", "pecan", "hazelnut", "walnut"], "offerIDs": [], "layout": "carousel"}, {"id": "recommended", "kind": "products", "enabled": true, "titles": {"tr": "Senin için", "en": "Recommended", "de": "Empfehlungen"}, "subtitles": {"tr": "", "en": "", "de": ""}, "productIDs": ["icedVanilla", "cheesecake", "croissant"], "offerIDs": [], "layout": "list"}]}"#.utf8)
        return (try? JSONDecoder().decode(HomeLayout.self, from: data)) ?? HomeLayout(version: 0, sections: [])
    }
    static func cached() -> HomeLayout {
        guard let data = UserDefaults.standard.data(forKey: "homeLayout.cache"),
              let value = try? JSONDecoder().decode(HomeLayout.self, from: data) else { return starter }
        return value
    }
}
