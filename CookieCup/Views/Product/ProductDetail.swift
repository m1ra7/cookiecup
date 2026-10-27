import SwiftUI

@MainActor
struct ProductDetail: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var options = ProductOptions()
    @State private var quantity = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let product: Product

    private var isFavorite: Bool { store.state.favorites.contains(product.id) }
    private var unitPrice: Int { product.cents + (product.isCoffee ? options.surcharge(for: product) : 0) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                productPresentation
                if product.isCoffee { customization }
                information
            }.padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 24)
        }
        .cafePage()
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { purchaseBar }
        .compatibleFeedback(.selection, trigger: isFavorite)
        .compatibleFeedback(.selection, trigger: options)
        .compatibleFeedback(.selection, trigger: quantity)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
            }.accessibilityLabel(copy.text("detailBack"))
            Spacer(minLength: 4)
            Text("CookieCup").font(CafeTypography.script(27))
            Spacer(minLength: 4)
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { store.favorite(product) }
            } label: {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 20)).frame(width: 44, height: 44)
                    .background(CafePalette.cream.opacity(isFavorite ? 0.12 : 0.04), in: Circle())
            }.accessibilityLabel(copy.text("favorites"))
                .accessibilityValue(copy.text(isFavorite ? "detailSaved" : "detailNotSaved"))
        }.buttonStyle(.plain).foregroundColor(CafePalette.cream)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(CafePalette.background.ignoresSafeArea(edges: .top))
    }

    private var productPresentation: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
            VStack(alignment: .leading, spacing: 10) {
                Text(product.name(copy))
                    .font(CafeTypography.script(29)).foregroundColor(CafePalette.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Text(product.description(copy))
                    .font(.subheadline).lineSpacing(3)
                    .foregroundColor(CafePalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Rectangle().fill(CafePalette.cream.opacity(0.1)).frame(height: 1)
                    .padding(.vertical, 4)
                HStack(alignment: .firstTextBaseline) {
                    Text(copy.text("detailUnitPrice")).font(.caption)
                        .foregroundColor(CafePalette.secondary)
                    Spacer(minLength: 8)
                    Text(copy.money(unitPrice)).font(CafeTypography.script(25, relativeTo: .title2))
                        .foregroundColor(CafePalette.cream).monospacedDigit()
                }
            }.padding(20).padding(.top, -4)
        }
        .background(CafePalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous)
            .stroke(CafePalette.cream.opacity(0.08), lineWidth: 1))
    }

    private var photo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(copy.text(product.category.key), systemImage: product.category.symbol)
                .font(.caption.weight(.medium)).foregroundColor(CafePalette.cream)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(CafePalette.cream.opacity(0.08), in: Capsule())
                .padding(.horizontal, 18).padding(.top, 16)
            CachedProductImage(imageName: product.imageName, imagePath: product.imagePath).scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: product.isCoffee ? 208 : 184)
                .padding(.horizontal, 30).padding(.bottom, 12)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 8)
                .accessibilityLabel(product.name(copy))
        }
        .background(LinearGradient(colors: [CafePalette.header, CafePalette.surface],
                                   startPoint: .top, endPoint: .bottom))
    }

    private var customization: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(copy.text("detailMakeItYours")).font(CafeTypography.script(24, relativeTo: .title2))
                .foregroundColor(CafePalette.cream)
            CafePanel {
                VStack(alignment: .leading, spacing: 16) {
                    optionPicker("size", selection: $options.size, values: ["regular", "large"])
                    optionPicker("milk", selection: $options.milk, values: ["whole", "oat", "noMilk"])
                    optionPicker("sugar", selection: $options.sugar, values: ["none", "one", "two"])
                    optionPicker("extras", selection: $options.extra, values: ["none", "shot", "vanilla"])
                }
            }
        }
    }
    private func optionPicker(_ key: String, selection: Binding<String>, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(copy.text(key)).font(.system(size: 13, weight: .semibold))
                .foregroundColor(CafePalette.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    ForEach(values, id: \.self) { value in optionButton(value, selection: selection) }
                }
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(values, id: \.self) { value in optionButton(value, selection: selection) }
                }
            }
        }
    }
    private func optionButton(_ value: String, selection: Binding<String>) -> some View {
        let selected = selection.wrappedValue == value
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { selection.wrappedValue = value }
        } label: {
            VStack(spacing: 3) {
                Text(copy.text("option." + value))
                if let surcharge = optionSurcharge(value) {
                    Text("+" + copy.money(surcharge)).font(.caption2).opacity(0.8)
                }
            }
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 12).padding(.vertical, 7).frame(minHeight: 44)
                .foregroundColor(selected ? CafePalette.surface : CafePalette.cream)
                .background(selected ? CafePalette.cream : CafePalette.header,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func optionSurcharge(_ value: String) -> Int? {
        // Derive displayed supplements from the same pricing model as the cart.
        var sample = ProductOptions()
        switch value {
        case "large": sample.size = value
        case "oat": sample.milk = value
        case "shot", "vanilla": sample.extra = value
        default: return nil
        }
        return sample.surcharge(for: product)
    }

    private var information: some View {
        Group {
            if product.ingredients != nil { liveInformation }
            else if let details = product.drinkDetails {
                drinkInformation(details)
            } else {
                standardInformation
            }
        }
    }

    private var liveInformation: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(copy.text("detailProductInfo")).font(CafeTypography.script(24)).foregroundColor(CafePalette.cream)
            if let calories = product.calories {
                Text((product.isEstimate == true ? "≈ " : "") + "\(calories) kcal").font(.title2.weight(.semibold)).foregroundColor(CafePalette.cream)
            } else { SettingsNote(key: "calorieUnavailable") }
            liveBlock("ingredients", symbol: "leaf", value: product.ingredients)
            liveBlock("drink.recipe", symbol: "list.number", value: product.recipes)
            liveBlock("allergens", symbol: "exclamationmark.shield", value: product.allergens)
            SettingsNote(key: "nutritionNotice")
        }
    }
    private func liveBlock(_ title: String, symbol: String, value: [String: String]?) -> some View {
        CafePanel {
            VStack(alignment: .leading, spacing: 10) {
                Label(copy.text(title), systemImage: symbol).font(.headline).foregroundColor(CafePalette.cream)
                Text(value?[copy.language] ?? value?["en"] ?? "—").font(.footnote).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true).foregroundColor(CafePalette.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func drinkInformation(_ details: DrinkDetails) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(copy.text("detailProductInfo"))
                .font(CafeTypography.script(24, relativeTo: .title2))
                .foregroundColor(CafePalette.cream)
            CafePanel {
                VStack(alignment: .leading, spacing: 16) {
                    informationBlock("drink.portion", symbol: "scalemass", text: "portion." + product.id)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(copy.text("drink.energy")).font(.subheadline.weight(.semibold))
                        Text((details.isEstimate ? "≈ " : "") + "\(details.calories) kcal")
                            .font(.title2.weight(.semibold)).monospacedDigit()
                        if details.containsAlcohol {
                            Text(copy.text("drink.alcohol"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(CafePalette.header, in: Capsule())
                        }
                    }.foregroundColor(CafePalette.cream)
                    informationDivider
                    informationBlock("ingredients", symbol: "leaf", text: "ingredients." + product.id)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            CafePanel {
                informationBlock(details.isEstimate ? "drink.recipe" : "drink.serving",
                                 symbol: "list.number", text: "recipe." + product.id)
            }
            CafePanel {
                informationBlock("allergens", symbol: "exclamationmark.shield",
                                 text: details.containsAlcohol ? "drink.allergensCocktail" : (details.isEstimate ? "allergens." + product.id : "drink.allergensCan"))
            }
            drinkFootnote(details)
        }.foregroundColor(CafePalette.secondary)
    }

    private var informationDivider: some View {
        Rectangle().fill(CafePalette.cream.opacity(0.09)).frame(height: 1)
    }

    private func drinkFootnote(_ details: DrinkDetails) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(copy.text(details.isEstimate ? (details.containsAlcohol ? "drink.estimate" : "food.estimate") : "drinkNote." + product.id))
                .fixedSize(horizontal: false, vertical: true)
            if !details.sourceURL.isEmpty, let url = URL(string: details.sourceURL) {
                Link(destination: url) {
                    Label(copy.text("drink.source"), systemImage: "arrow.up.right.square")
                        .foregroundColor(CafePalette.cream)
                        .padding(.vertical, 8)
                }
            }
        }.font(.caption).lineSpacing(3).padding(.horizontal, 4)
    }

    private var standardInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(copy.text("detailProductInfo"))
                .font(CafeTypography.script(24, relativeTo: .title2))
                .foregroundColor(CafePalette.cream)
            CafePanel {
                VStack(alignment: .leading, spacing: 16) {
                    informationBlock("ingredients", symbol: "leaf", text: "ingredients." + product.category.rawValue)
                    Rectangle().fill(CafePalette.cream.opacity(0.09)).frame(height: 1)
                    informationBlock("allergens", symbol: "exclamationmark.shield", text: "allergens." + product.category.rawValue)
                }.foregroundColor(CafePalette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.text("calorieUnavailable"))
                Text(copy.text("ratingUnavailable"))
                Text(copy.text("nutritionNotice")).padding(.top, 3)
            }.font(.caption).lineSpacing(2)
                .foregroundColor(CafePalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }
    private func informationBlock(_ title: String, symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .foregroundColor(CafePalette.cream)
                .frame(width: 38, height: 38)
                .background(CafePalette.header, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.text(title)).font(.subheadline.weight(.semibold)).foregroundColor(CafePalette.cream)
                Text(copy.text(text)).font(.footnote).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var purchaseBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    quantityControl
                    addButton
                }
            } else {
                HStack(spacing: 12) {
                    quantityControl
                    addButton
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(CafePalette.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { CafePalette.cream.opacity(0.08).frame(height: 1) }
    }

    private var addButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                store.add(product, options: options, quantity: quantity)
            }
        } label: {
            VStack(spacing: 3) {
                Text(copy.text("add")).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(copy.money(unitPrice * quantity)).font(.footnote.weight(.medium)).monospacedDigit()
            }
            .frame(maxWidth: .infinity).frame(minHeight: 54)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundColor(CafePalette.surface)
            .background(CafePalette.cream, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).disabled(product.stock == 0 || product.active == false)
            .accessibilityLabel(copy.text("add") + ", " + copy.text("total") + ": " + copy.money(unitPrice * quantity))
    }
    private var quantityControl: some View {
        HStack(spacing: 4) {
            quantityButton("minus", key: "decrease", disabled: quantity == 1) { quantity -= 1 }
            Text("\(quantity)").font(.headline.monospacedDigit()).frame(minWidth: 24)
                .accessibilityLabel(copy.text("quantity") + ": \(quantity)")
            quantityButton("plus", key: "increase", disabled: quantity == 20) { quantity += 1 }
        }.foregroundColor(CafePalette.cream)
            .background(CafePalette.header, in: Capsule())
    }
    private func quantityButton(_ symbol: String, key: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44)
        }.buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.3 : 1)
            .accessibilityLabel(copy.text(key))
    }
}
