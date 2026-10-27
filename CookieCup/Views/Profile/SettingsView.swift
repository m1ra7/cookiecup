import SwiftUI

@MainActor
struct CookieCupSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.copy) private var copy
    @ObservedObject private var accounts = AccountStore.shared
    var body: some View {
        NavigationStack {
            SettingsPage(title: "settings") {
                VStack(spacing: 12) {
                    NavigationLink { LanguageSettingsView() } label: { SettingsRow(title: "language", subtitle: "settings.languageHint", symbol: "globe") }
                    NavigationLink { NotificationsView() } label: { SettingsRow(title: "platform.notifications", subtitle: "platform.notificationsHint", symbol: "bell") }
                    NavigationLink { LegalSettingsView(kind: "privacy") } label: { SettingsRow(title: "platform.privacy", subtitle: "platform.privacyHint", symbol: "hand.raised") }
                    NavigationLink { LegalSettingsView(kind: "terms") } label: { SettingsRow(title: "platform.terms", subtitle: "platform.termsHint", symbol: "doc.text") }
                    NavigationLink { DeleteAccountSettingsView() } label: { SettingsRow(title: "settings.deleteAccount", subtitle: "settings.deleteNotice", symbol: "trash") }
                    NavigationLink { AboutSettingsView() } label: { SettingsRow(title: "about", subtitle: "settings.aboutHint", symbol: "info.circle") }
                }.buttonStyle(.plain)

            }
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 36, height: 36) }
                    .accessibilityLabel(copy.text("settingsClose"))
            } }
        }.tint(CafePalette.cream).preferredColorScheme(.dark)
    }
}

@MainActor
struct SettingsPage<Content: View>: View {
    @Environment(\.copy) private var copy
    let title: String
    let content: Content
    init(title: String, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }.padding(20)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively)
            .foregroundColor(CafePalette.cream).cafePage()
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(CafePalette.header, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationTitle(copy.text(title)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) {
                Text(copy.text(title)).font(CafeTypography.script(25)).foregroundColor(CafePalette.cream)
            } }
    }
}
@MainActor
struct SettingsNote: View {
    @Environment(\.copy) private var copy
    let key: String
    var body: some View { Text(copy.text(key)).font(.footnote).foregroundColor(CafePalette.secondary).fixedSize(horizontal: false, vertical: true) }
}
@MainActor
private struct SettingsRow: View {
    @Environment(\.copy) private var copy
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 22)).frame(width: 43, height: 48)
                .background(CafePalette.header, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(copy.text(title)).font(.headline)
                Text(copy.text(subtitle)).font(.caption).foregroundColor(CafePalette.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
        }.padding(16).background(CafePalette.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}
@MainActor
struct SettingsInput: View {
    @Environment(\.copy) private var copy
    let key: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var secure = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(copy.text(key)).font(.caption.weight(.semibold)).foregroundColor(CafePalette.secondary)
            Group {
                if secure {
                    SecureField(copy.text(key), text: $text).keyboardType(keyboard)
                        .textContentType(key == "settings.cardNumber" ? .creditCardNumber : .password)
                } else {
                    TextField(copy.text(key), text: $text).keyboardType(keyboard)
                        .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                }
            }.autocorrectionDisabled().padding(14)
                .background(CafePalette.header, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityLabel(copy.text(key))
        }
    }
}
@MainActor
struct SettingsError: View {
    @Environment(\.copy) private var copy
    let key: String?
    var body: some View {
        if let key = key {
            Text(copy.text(key)).font(.footnote).foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently)
        }
    }
}
func settingsErrorKey(_ error: Error) -> String {
    if let cloud = error as? CloudFailure { return cloud.key }
    return (error as? AccountFailure)?.rawValue ?? "settings.storageError"
}

@MainActor
private struct LanguageSettingsView: View {
    @Environment(\.copy) private var copy
    @AppStorage("language") private var language = "en"
    var body: some View {
        SettingsPage(title: "language") {
            ForEach(["tr", "de", "en"], id: \.self) { value in
                Button { language = value } label: {
                    HStack {
                        Text(["tr": "Türkçe", "de": "Deutsch", "en": "English"][value] ?? value)
                        Spacer()
                        if language == value { Image(systemName: "checkmark.circle.fill") }
                    }.padding(20).background(CafePalette.surface, in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityAddTraits(language == value ? .isSelected : [])
            }
        }.compatibleFeedback(.selection, trigger: language)
    }
}
@MainActor
private struct AboutSettingsView: View {
    @Environment(\.copy) private var copy
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "1.0") (\(info["CFBundleVersion"] as? String ?? "1"))"
    }
    var body: some View {
        SettingsPage(title: "about") {
            CafePanel {
                VStack(alignment: .leading, spacing: 14) {
                    Text("CookieCup").font(CafeTypography.script(39))
                    Text(copy.text("settings.aboutBody")).font(.subheadline)
                    Text(copy.text("settings.developerCredit")).font(.subheadline)
                        .foregroundColor(CafePalette.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(copy.text("settings.version") + " " + version).font(.caption).foregroundColor(CafePalette.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsNote(key: "demoNotice")
            SettingsNote(key: "settings.localNotice")
            SettingsNote(key: "settings.cardNotice")
            SettingsNote(key: "catalogNotice")
        }
    }
}

@MainActor
struct SettingsLoginPrompt: View {
    @Environment(\.copy) private var copy
    var body: some View {
        CafePanel {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "person.crop.circle").font(.system(size: 36))
                Text(copy.text("settings.loginRequired")).font(.subheadline)
                NavigationLink { AccountSettingsView() } label: { Text(copy.text("settings.login")) }
                    .buttonStyle(CafePrimaryButton())
            }
        }
    }
}
