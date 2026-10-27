import SwiftUI
import UIKit
import ImageIO

@MainActor
struct ProductPhoto: View {
    @Environment(\.copy) private var copy
    let product: Product
    var body: some View {
        CachedProductImage(imageName: product.imageName, imagePath: product.imagePath).scaledToFit().padding(18)
            .frame(maxWidth: .infinity).background(Theme.photo)
            .accessibilityLabel(product.name(copy))
    }
}

private enum ProductCardColors {
    static let background = Color(red: 0.18, green: 0.09, blue: 0.035)
    static let secondary = Color(red: 0.79, green: 0.73, blue: 0.69)
}

/// Rounded upper corners and a softly curved lower-right corner, as in the reference.
private struct CafeCardShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = min(27, rect.width * 0.16)
        let curveX = min(rect.width * 0.64, rect.width - r - 4)
        let curveY = min(145, rect.height * 0.46)
        var path = Path()
        path.move(to: CGPoint(x: r, y: 0))
        path.addLine(to: CGPoint(x: rect.width - r, y: 0))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: r), control: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - curveY))
        path.addQuadCurve(to: CGPoint(x: rect.width - curveX, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: r, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - r), control: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: .zero)
        path.closeSubpath()
        return path
    }
}

struct ProductCardMetrics {
    let width: CGFloat
    let imageSize: CGFloat
    let titleHeight: CGFloat
    let descriptionHeight: CGFloat
    let height: CGFloat
}

private final class CachedCardMetrics: NSObject {
    let value: ProductCardMetrics
    init(_ value: ProductCardMetrics) { self.value = value }
}

enum ProductCardLayout {
    static let width: CGFloat = 204
    static let imageToName: CGFloat = 6
    static let nameToDescription: CGFloat = 2
    private static let cache: NSCache<NSString, CachedCardMetrics> = { let value = NSCache<NSString, CachedCardMetrics>(); value.countLimit = 64; return value }()

    static func metrics(for product: Product, copy: Copy) -> ProductCardMetrics {
        let catalogVersion: String = String(Catalog.revision)
        let keyParts: [String] = [copy.language, descriptionLines(for: product) == 2 ? "all-drinks" : product.categoryID, catalogVersion]
        let keyText: String = keyParts.joined(separator: ":")
        let key: NSString = keyText as NSString
        if let cached = cache.object(forKey: key) { return cached.value }
        let compact: Bool
        switch product.category {
        case .coffee, .coldCoffee, .coldDrinks, .tea: compact = true
        default: compact = false
        }
        if compact {
            // Use the exact card dimensions from the cookie shelf (Most Popular).
            let reference = Catalog.products.first { $0.category == .cookies }
            let referenceHeight = reference.map { metrics(for: $0, copy: copy).height } ?? 280
            let imageSize: CGFloat = 90
            let drinks = Catalog.products.filter { isDrink($0) }
            let group = drinks.isEmpty ? [product] : drinks
            let titleFont = UIFont(name: "Pacifico-Regular", size: 20) ?? UIFont.systemFont(ofSize: 20)
            let descriptionFont = UIFont.systemFont(ofSize: 15)
            let textBudget = referenceHeight - imageSize - imageToName - nameToDescription - 64
            let minimumDescription = ceil(descriptionFont.lineHeight) + 2
            let titleHeight = min(maximumTextHeight(products: group, copy: copy, width: width, isTitle: true),
                                  min(ceil(titleFont.lineHeight * 2) + 2, max(minimumDescription, textBudget - minimumDescription)))
            let descriptionHeight = max(minimumDescription, min(ceil(descriptionFont.lineHeight * 2 + 3) + 2, textBudget - titleHeight))
            let result = ProductCardMetrics(width: width, imageSize: imageSize,
                titleHeight: titleHeight, descriptionHeight: descriptionHeight, height: referenceHeight)
            cache.setObject(CachedCardMetrics(result), forKey: key)
            return result
        }
        let cardWidth: CGFloat = width
        // Existing non-drink card sizes stay unchanged.
        let imageSize: CGFloat
        switch product.category {
        case .coffee, .coldCoffee, .coldDrinks, .tea: imageSize = 90
        case .snacks, .desserts: imageSize = 112
        default: imageSize = 90
        }
        let group = Catalog.products.filter { candidate in
            candidate.category == product.category
        }
        let products = group.isEmpty ? [product] : group
        let titleHeight = maximumTextHeight(products: products, copy: copy, width: cardWidth, isTitle: true)
        let descriptionHeight = products.reduce(CGFloat.zero) { maximum, item in
            let fullHeight = maximumTextHeight(products: [item], copy: copy, width: cardWidth, isTitle: false)
            guard let lines = descriptionLineLimit(for: item, copy: copy) else { return max(maximum, fullHeight) }
            let limitedHeight = ceil(UIFont.systemFont(ofSize: 15).lineHeight * CGFloat(lines) + CGFloat(lines - 1) * 3) + 2
            return max(maximum, min(fullHeight, limitedHeight))
        }
        // Measure each complete card instead of combining the longest name with
        // another product's longest description, which exaggerated the height.
        let contentHeight = products.reduce(CGFloat.zero) { maximum, item in
            let nameHeight = maximumTextHeight(products: [item], copy: copy, width: cardWidth, isTitle: true)
            let fullHeight = maximumTextHeight(products: [item], copy: copy, width: cardWidth, isTitle: false)
            let textHeight: CGFloat
            if let lines = descriptionLineLimit(for: item, copy: copy) {
                let limit = ceil(UIFont.systemFont(ofSize: 15).lineHeight * CGFloat(lines) + CGFloat(lines - 1) * 3) + 2
                textHeight = min(fullHeight, limit)
            } else { textHeight = fullHeight }
            return max(maximum, imageSize + imageToName + nameHeight + nameToDescription + textHeight + 64)
        }
        let result = ProductCardMetrics(width: cardWidth, imageSize: imageSize,
            titleHeight: titleHeight, descriptionHeight: descriptionHeight,
            height: max(260, contentHeight))
        cache.setObject(CachedCardMetrics(result), forKey: key)
        return result
    }

    static func isDrink(_ product: Product) -> Bool {
        switch product.category {
        case .coffee, .coldCoffee, .coldDrinks, .tea: return true
        default: return false
        }
    }

    // Limit by the actual space in the shared card, not by a character count.
    static func drinkDescriptionLines(_ metrics: ProductCardMetrics) -> Int {
        let lineHeight = UIFont.systemFont(ofSize: 15).lineHeight + 3
        return max(1, min(2, Int((metrics.descriptionHeight + 3) / lineHeight)))
    }

    static func descriptionLineLimit(for product: Product, copy: Copy) -> Int? {
        let text = product.description(copy).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count <= 100 ? nil : descriptionLines(for: product)
    }

    static func descriptionLines(for product: Product) -> Int {
        switch product.category {
        case .coffee, .coldCoffee, .coldDrinks, .tea: return 2
        default: return 3
        }
    }

    private static func maximumTextHeight(products: [Product], copy: Copy, width: CGFloat, isTitle: Bool) -> CGFloat {
        let font = isTitle
            ? (UIFont(name: "Pacifico-Regular", size: 20) ?? UIFont.systemFont(ofSize: 20))
            : UIFont.systemFont(ofSize: 15)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = isTitle ? 0 : 3
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        return products.reduce(CGFloat.zero) { maximum, product in
            let text = isTitle ? product.name(copy) : product.description(copy)
            let bounds = (text as NSString).boundingRect(
                with: CGSize(width: width - 32, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes, context: nil)
            return max(maximum, ceil(bounds.height) + 2)
        }
    }
}

@MainActor
struct ProductCard: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let product: Product
    private var isFavorite: Bool { store.state.favorites.contains(product.id) }
    private var isDrink: Bool { ProductCardLayout.isDrink(product) }
    private var metrics: ProductCardMetrics { ProductCardLayout.metrics(for: product, copy: copy) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            productLink
            Spacer(minLength: 0)
            priceActions.padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 8)
        }
        .frame(width: metrics.width, height: metrics.height, alignment: .top)
        .background(cardBackground)
        .overlay(alignment: .topTrailing) { favoriteButton }
        .compatibleFeedback(.selection, trigger: isFavorite)
    }

    private var productLink: some View {
        NavigationLink(value: product) {
            VStack(alignment: .leading, spacing: 0) {
                CachedProductImage(imageName: product.imageName, imagePath: product.imagePath).scaledToFit()
                    .frame(width: metrics.imageSize, height: metrics.imageSize)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, ProductCardLayout.imageToName)
                    .accessibilityHidden(true)
                Text(product.name(copy))
                    .font(CafeTypography.productTitle).foregroundColor(.white)
                    .lineLimit(isDrink ? 2 : nil).truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, ProductCardLayout.nameToDescription)
                Text(product.description(copy))
                    .font(.system(size: 12)).foregroundColor(ProductCardColors.secondary)
                    .lineSpacing(3).lineLimit(isDrink ? ProductCardLayout.drinkDescriptionLines(metrics) : ProductCardLayout.descriptionLineLimit(for: product, copy: copy))
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: isDrink ? metrics.descriptionHeight : nil, alignment: .topLeading)
            }.padding(.horizontal, 16)
        }.buttonStyle(.plain)
    }

    private var cardBackground: some View {
        CafeCardShape().fill(ProductCardColors.background)
            .shadow(color: ProductCardColors.secondary.opacity(0.20), radius: 7, y: 3)
            .padding(.top, 42)
    }

    private var priceActions: some View {
        HStack(spacing: 5) {
            Text(copy.money(product.cents))
                .font(CafeTypography.script(24, relativeTo: .headline))
                .foregroundColor(ProductCardColors.secondary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85)) { store.add(product) }
            } label: {
                Image(systemName: "plus").font(.system(size: 25, weight: .light))
                    .foregroundColor(.white).frame(width: 50, height: 50)
                    .background(Color.black, in: Circle())
            }.buttonStyle(.plain)
                .offset(x: 18)
                .accessibilityLabel(copy.text("add"))
        }
    }

    private var favoriteButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { store.favorite(product) }
        } label: {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .medium)).foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.32), in: Circle())
        }.buttonStyle(.plain)
            .padding(.top, 47).padding(.trailing, 4)
            .accessibilityLabel(copy.text("favorites"))
    }
}

@MainActor
struct ProductGrid: View {
    let products: [Product]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: ProductCardLayout.width, maximum: ProductCardLayout.width), spacing: 16)], alignment: .center, spacing: 22) {
            ForEach(products) { ProductCard(product: $0) }
        }
    }
}

// Cache only immutable, same-origin product images. Session credentials are never sent.
private actor ProductImageCache {
    static let shared = ProductImageCache()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 96 * 1024 * 1024, diskPath: "cookiecup-products")
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        memory.totalCostLimit = 32 * 1024 * 1024
    }
    func image(_ url: URL) async throws -> UIImage {
        if let image = memory.object(forKey: url as NSURL) { return image }
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count <= 6 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        let image = UIImage(cgImage: cg)
        memory.setObject(image, forKey: url as NSURL, cost: cg.bytesPerRow * cg.height)
        return image
    }
}
@MainActor
struct CachedProductImage: View {
    let imageName: String
    let imagePath: String?
    @State private var remote: UIImage?
    @State private var failed = false
    private var url: URL? {
        guard let path = imagePath, path.hasPrefix("/media/products/"), !path.contains("..") else { return nil }
        return APIClient.origin.appendingPathComponent(String(path.dropFirst()))
    }
    var body: some View {
        Group {
            if let image = remote { Image(uiImage: image).resizable().interpolation(.high).scaledToFit() }
            else if !imageName.isEmpty, UIImage(named: imageName) != nil { Image(imageName).resizable().interpolation(.high).scaledToFit() }
            else { VStack { if failed { Image(systemName: "wifi.exclamationmark") } else { ProgressView() } }.frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .task(id: url) {
            remote = nil; failed = false
            guard let url = url else { return }
            do { let image = try await ProductImageCache.shared.image(url); if !Task.isCancelled { remote = image } }
            catch { if !Task.isCancelled { failed = true } }
        }
    }
}
