import SwiftUI
import UIKit

enum Theme {
    static let coffee = Color(red: 0.39, green: 0.25, blue: 0.18)
    static let caramel = Color(red: 0.69, green: 0.44, blue: 0.25)
    static let cream = Color(red: 0.94, green: 0.88, blue: 0.79)
    static let photo = Color(red: 0.91, green: 0.85, blue: 0.75)
    static let background = Color("Canvas")
    static let card = Color("Card")
}
struct CoffeeButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(Theme.coffee, in: RoundedRectangle(cornerRadius: 20)).foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
struct EmptyState: View {
    @Environment(\.copy) private var copy
    let symbol: String
    let title: String
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .light)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(copy.text(title)).font(.title2.bold()).multilineTextAlignment(.center)
            Text(copy.text("emptyHint")).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
struct OptionSummary: View {
    @Environment(\.copy) private var copy
    let options: ProductOptions
    var body: some View { Text([options.size, options.milk, options.sugar, options.extra].map { copy.text("option." + $0) }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
}

// UIKit is used only for the haptic API available on iOS 16.
enum CompatibleFeedback { case selection, success }
private struct CompatibleFeedbackModifier<Value: Equatable>: ViewModifier {
    let kind: CompatibleFeedback
    let trigger: Value
    func body(content: Content) -> some View {
        content.onChange(of: trigger) { _ in
            switch kind {
            case .selection: UISelectionFeedbackGenerator().selectionChanged()
            case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}
extension View {
    func compatibleFeedback<Value: Equatable>(_ kind: CompatibleFeedback, trigger: Value) -> some View {
        modifier(CompatibleFeedbackModifier(kind: kind, trigger: trigger))
    }
}

// Shared surfaces for the remaining tabs, matching Home and Menu.
enum CafePalette {
    static let background = Color(red: 0.25, green: 0.15, blue: 0.13)
    static let header = Color(red: 0.31, green: 0.20, blue: 0.18)
    static let surface = Color(red: 0.18, green: 0.09, blue: 0.035)
    static let cream = Color(red: 0.94, green: 0.88, blue: 0.79)
    static let secondary = Color(red: 0.79, green: 0.73, blue: 0.69)
}

struct CafePageHeader: View {
    @Environment(\.copy) private var copy
    let titleKey: String
    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 42, height: 42)
            Spacer(minLength: 0)
            Text(copy.text(titleKey)).font(CafeTypography.script(33))
                .foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.65)
            Spacer(minLength: 0)
            Color.clear.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(CafePalette.header.ignoresSafeArea(edges: .top))
    }
}

private struct CafePageModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(CafePalette.background.ignoresSafeArea())
            .foregroundColor(.white)
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(CafePalette.surface, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)
    }
}
extension View { func cafePage() -> some View { modifier(CafePageModifier()) } }

struct CafePanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(CafePalette.surface, in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(CafePalette.cream.opacity(0.08), lineWidth: 1))
    }
}

struct CafePrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundColor(CafePalette.surface)
            .background(CafePalette.cream, in: RoundedRectangle(cornerRadius: 19))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct CafeEmptyState: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    let symbol: String
    let titleKey: String
    var body: some View {
        VStack(spacing: 19) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light))
                .foregroundColor(CafePalette.cream).frame(width: 96, height: 96)
                .background(CafePalette.cream.opacity(0.07), in: Circle())
                .accessibilityHidden(true)
            Text(copy.text(titleKey)).font(CafeTypography.script(27))
                .foregroundColor(.white).multilineTextAlignment(.center)
            Text(copy.text("emptyHint")).font(.subheadline)
                .foregroundColor(CafePalette.secondary).multilineTextAlignment(.center)
            Button(copy.text("discover")) { store.selectedTab = 1 }
                .buttonStyle(CafePrimaryButton()).padding(.top, 5)
        }.padding(30).frame(maxWidth: 380)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
