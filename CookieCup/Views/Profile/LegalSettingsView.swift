import SwiftUI

struct LegalDocument: Decodable {
    let title: String
    let body: String
    let published: Bool
    let version: Int
    let `operator`: String
    let address: String
    let contactEmail: String
    let retention: String
}
@MainActor
struct LegalSettingsView: View {
    @Environment(\.copy) private var copy
    let kind: String
    @State private var document: LegalDocument?
    @State private var errorKey: String?
    @State private var loading = false
    var body: some View {
        SettingsPage(title: kind == "privacy" ? "platform.privacy" : "platform.terms") {
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if let document = document {
                if !document.published { SettingsNote(key: "platform.legalDraft") }
                CafePanel {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(document.title).font(CafeTypography.script(26))
                        if !document.operator.isEmpty { Text(document.operator).font(.headline) }
                        if !document.address.isEmpty { Text(document.address) }
                        if !document.contactEmail.isEmpty { Text(document.contactEmail).textSelection(.enabled) }
                        Text(document.body).font(.subheadline).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        if !document.retention.isEmpty { Text(document.retention).font(.footnote) }
                        Text(copy.text("settings.version") + " \(document.version)").font(.caption).foregroundColor(CafePalette.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            SettingsError(key: errorKey)
            if errorKey != nil { Button(copy.text("platform.retry")) { Task { await load() } }.buttonStyle(CafePrimaryButton()) }
        }.task(id: copy.language) { await load() }
    }
    private func load() async {
        guard APIClient.shared.supportsPlatform else { errorKey = "platform.awaitingActivation"; return }
        loading = true; errorKey = nil
        do { document = try await APIClient.shared.getV2("legal/" + kind, query: [URLQueryItem(name: "lang", value: copy.language)]) }
        catch { errorKey = settingsErrorKey(error) }
        loading = false
    }
}
@MainActor
struct DeleteAccountSettingsView: View {
    @Environment(\.copy) private var copy
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var accounts = AccountStore.shared
    @State private var password = ""
    @State private var busy = false
    @State private var confirmation = false
    @State private var errorKey: String?
    var body: some View {
        SettingsPage(title: "settings.deleteAccount") {
            if accounts.account != nil {
                CafePanel {
                    VStack(alignment: .leading, spacing: 18) {
                        SettingsNote(key: "settings.deleteNotice")
                        SettingsInput(key: "settings.currentPassword", text: $password, secure: true)
                        SettingsError(key: errorKey)
                        Button(role: .destructive) { confirmation = true } label: {
                            HStack { if busy { ProgressView() }; Label(copy.text("settings.deleteAccount"), systemImage: "trash") }.frame(maxWidth: .infinity, minHeight: 48)
                        }.disabled(busy || password.isEmpty)
                    }
                }
            } else { SettingsLoginPrompt() }
        }.disabled(busy).interactiveDismissDisabled(busy).navigationBarBackButtonHidden(busy)
            .alert(copy.text("settings.deleteAccount"), isPresented: $confirmation) {
                Button(copy.text("settings.cancel"), role: .cancel) {}
                Button(copy.text("settings.delete"), role: .destructive) {
                    busy = true
                    Task { @MainActor in
                        var deleted = false
                        do { try await accounts.deleteAccount(password: password); deleted = true }
                        catch { errorKey = settingsErrorKey(error) }
                        password = ""; busy = false
                        if deleted { dismiss() }
                    }
                }
            } message: { Text(copy.text("settings.deleteNotice")) }
            .onDisappear { password = "" }
    }
}
