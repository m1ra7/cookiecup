import SwiftUI

@MainActor
struct CardSettingsView: View {
    @Environment(\.copy) private var copy
    @ObservedObject private var accounts = AccountStore.shared
    @State private var adding = false
    @State private var deleting: CafeCard?
    @State private var errorKey: String?
    @State private var busy = false
    var body: some View {
        SettingsPage(title: "settings.cards") {
            SettingsNote(key: "settings.cardNotice")
            if let account = accounts.account {
                if account.cards.isEmpty { SettingsNote(key: "settings.noCards") }
                ForEach(account.cards) { card in cardRow(card, isDefault: account.defaultCardID == card.id) }
                Button { adding = true } label: {
                    Label(copy.text("settings.addCard"), systemImage: "plus")
                }.buttonStyle(CafePrimaryButton())
            } else { SettingsLoginPrompt() }
            SettingsError(key: errorKey)
        }
        .disabled(busy)
        .sheet(isPresented: $adding) {
            NavigationStack { CardEditor() }.preferredColorScheme(.dark).tint(CafePalette.cream)
        }
        .alert(copy.text("settings.deleteCard"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(copy.text("settings.cancel"), role: .cancel) { deleting = nil }
            Button(copy.text("settings.delete"), role: .destructive) {
                if let card = deleting { run { try await accounts.removeCard(card.id) } }
                deleting = nil
            }
        }
    }
    private func cardRow(_ card: CafeCard, isDefault: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "creditcard.fill").font(.title2)
                Text(card.brand.isEmpty ? copy.text("settings.bankCard") : card.brand).font(.headline)
                Spacer()
                if isDefault { Image(systemName: "checkmark.circle.fill").accessibilityLabel(copy.text("settings.default")) }
            }
            Text("••••  ••••  ••••  " + card.lastFour).font(.system(.title3, design: .monospaced)).minimumScaleFactor(0.7).lineLimit(1)
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(card.holder).font(.subheadline.weight(.medium))
                    Text(card.expiry).font(.caption).foregroundColor(CafePalette.secondary)
                }
                Spacer()
                Button { deleting = card } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                    .accessibilityLabel(copy.text("settings.deleteCard"))
            }
            if !isDefault {
                Button(copy.text("settings.makeDefault")) { run { try await accounts.defaultCard(card.id) } }.font(.subheadline).frame(minHeight: 44)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [CafePalette.header, CafePalette.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(CafePalette.cream.opacity(0.15), lineWidth: 1))
            .buttonStyle(.plain)
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { @MainActor in
            do { try await action(); errorKey = nil } catch { errorKey = settingsErrorKey(error) }
            busy = false
        }
    }
}
@MainActor
private struct CardEditor: View {
    @Environment(\.copy) private var copy
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var holder = ""
    @State private var number = ""
    @State private var month = ""
    @State private var year = ""
    @State private var errorKey: String?
    @State private var busy = false
    private var digits: String { CardValidation.digits(number) }
    private var expiryYear: Int { let value = Int(year) ?? 0; return year.count == 2 ? 2000 + value : value }
    private var valid: Bool {
        !holder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && CardValidation.validNumber(digits)
            && CardValidation.validExpiry(month: Int(month) ?? 0, year: expiryYear)
    }
    var body: some View {
        SettingsPage(title: "settings.addCard") {
            SettingsNote(key: "settings.cardNotice")
            CafePanel {
                VStack(spacing: 17) {
                    SettingsInput(key: "settings.cardHolder", text: $holder)
                    SettingsInput(key: "settings.cardNumber", text: $number, keyboard: .numberPad, secure: true)
                        .onChange(of: number) { newValue in
                            let clean = String(CardValidation.digits(newValue).prefix(19))
                            if clean != number { number = clean }
                        }
                    HStack(alignment: .top, spacing: 14) {
                        SettingsInput(key: "settings.expiryMonth", text: $month, keyboard: .numberPad)
                        SettingsInput(key: "settings.expiryYear", text: $year, keyboard: .numberPad)
                    }
                    SettingsNote(key: "settings.noCVV")
                }
            }
            SettingsError(key: errorKey)
            Button(copy.text("settings.saveCard")) { save() }.buttonStyle(CafePrimaryButton()).disabled(!valid)
        }.disabled(busy).interactiveDismissDisabled(busy).toolbar { ToolbarItem(placement: .navigationBarTrailing) {
            Button(copy.text("settings.cancel")) { number = ""; dismiss() }
        } }
        .onDisappear { number = "" }
        .onChange(of: scenePhase) { phase in if phase != .active { number = "" } }
    }
    private func save() {
        guard valid else { errorKey = "settings.invalidCard"; return }
        let card = CafeCard(holder: holder.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: CardValidation.brand(digits), lastFour: String(digits.suffix(4)), month: Int(month) ?? 0, year: expiryYear)
        number = ""
        guard !busy else { return }; busy = true
        Task { @MainActor in
            do { try await AccountStore.shared.saveCard(card); dismiss() }
            catch { errorKey = settingsErrorKey(error) }
            busy = false
        }
    }
}
