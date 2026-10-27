import SwiftUI

@MainActor
struct AddressSettingsView: View {
    @Environment(\.copy) private var copy
    @ObservedObject private var accounts = AccountStore.shared
    @State private var editing: CafeAddress?
    @State private var deleting: CafeAddress?
    @State private var errorKey: String?
    @State private var busy = false
    var body: some View {
        SettingsPage(title: "settings.addresses") {
            if let account = accounts.account {
                SettingsNote(key: "settings.addressNotice")
                if account.addresses.isEmpty { SettingsNote(key: "settings.noAddresses") }
                ForEach(account.addresses) { address in
                    addressRow(address, isDefault: account.defaultAddressID == address.id)
                }
                Button { editing = CafeAddress(recipient: account.name) } label: {
                    Label(copy.text("settings.addAddress"), systemImage: "plus")
                }.buttonStyle(CafePrimaryButton())
            } else { SettingsLoginPrompt() }
            SettingsError(key: errorKey)
        }
        .disabled(busy)
        .sheet(item: $editing) { address in
            NavigationStack { AddressEditor(address: address) }.preferredColorScheme(.dark).tint(CafePalette.cream)
        }
        .alert(copy.text("settings.deleteAddress"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(copy.text("settings.cancel"), role: .cancel) { deleting = nil }
            Button(copy.text("settings.delete"), role: .destructive) {
                if let address = deleting { run { try await accounts.removeAddress(address.id) } }
                deleting = nil
            }
        }
    }
    private func addressRow(_ address: CafeAddress, isDefault: Bool) -> some View {
        CafePanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(address.label, systemImage: "mappin.circle").font(.headline)
                    Spacer()
                    if isDefault { Text(copy.text("settings.default")).font(.caption).foregroundColor(CafePalette.secondary) }
                }
                Text(address.summary).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 18) {
                    Button(copy.text("settings.edit")) { editing = address }
                    Spacer()
                    Button { deleting = address } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                        .accessibilityLabel(copy.text("settings.deleteAddress"))
                }
                if !isDefault {
                    Button(copy.text("settings.makeDefault")) { run { try await accounts.defaultAddress(address.id) } }.frame(minHeight: 44)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(.plain)
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
private struct AddressEditor: View {
    @Environment(\.copy) private var copy
    @Environment(\.dismiss) private var dismiss
    @State var address: CafeAddress
    @State private var errorKey: String?
    @State private var busy = false
    var body: some View {
        SettingsPage(title: "settings.address") {
            CafePanel {
                VStack(spacing: 16) {
                    SettingsInput(key: "settings.addressLabel", text: $address.label)
                    SettingsInput(key: "settings.recipient", text: $address.recipient)
                    SettingsInput(key: "settings.street", text: $address.street)
                    SettingsInput(key: "settings.postalCode", text: $address.postalCode)
                    SettingsInput(key: "settings.city", text: $address.city)
                    SettingsInput(key: "settings.country", text: $address.country)
                    SettingsInput(key: "settings.phone", text: $address.phone, keyboard: .phonePad)
                }
            }
            SettingsError(key: errorKey)
            Button(copy.text("settings.save")) {
                guard !busy else { return }; busy = true
                Task { @MainActor in
                    do { try await AccountStore.shared.saveAddress(address); dismiss() }
                    catch { errorKey = settingsErrorKey(error) }
                    busy = false
                }
            }.buttonStyle(CafePrimaryButton()).disabled(!address.isValid)
        }.disabled(busy).interactiveDismissDisabled(busy).toolbar { ToolbarItem(placement: .navigationBarTrailing) {
            Button(copy.text("settings.cancel")) { dismiss() }
        } }
    }
}
