import SwiftUI

@MainActor
struct ProfileAccountSection: View {
    @EnvironmentObject private var store: ShopStore
    @Environment(\.copy) private var copy
    @ObservedObject private var accounts = AccountStore.shared
    @State private var registering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var errorKey: String?
    @State private var showAuthError = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let account = accounts.account {
                CafePanel {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(account.name).font(CafeTypography.script(28))
                        Text(account.email).font(.subheadline)
                        if store.hasGuestCart {
                            Button(copy.text("cloud.importCart")) { store.importGuestCart() }.disabled(store.syncing)
                        }
                        NavigationLink { ManageAccountView() } label: {
                            Label(copy.text("settings.manage"), systemImage: "person.crop.circle.badge.checkmark")
                        }.buttonStyle(CafePrimaryButton())
                        Button(copy.text("settings.logout")) { signOut() }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                            HStack(spacing: 12) {
                    NavigationLink { AddressSettingsView() } label: { Label(copy.text("settings.addresses"), systemImage: "mappin.and.ellipse") }
                    Spacer(minLength: 0)
                    NavigationLink { CardSettingsView() } label: { Label(copy.text("settings.cards"), systemImage: "creditcard") }
                }.font(.subheadline).padding(.vertical, 8)
            } else { authenticationForm }
            if accounts.restoring { ProgressView().tint(CafePalette.cream) }
            SettingsError(key: errorKey ?? accounts.errorKey)
            if accounts.account == nil && accounts.errorKey != nil {
                Button(copy.text("cloud.retry")) { Task { await accounts.restore() } }
            }
            SettingsNote(key: "settings.localNotice")

        }.disabled(busy || accounts.restoring).navigationBarBackButtonHidden(busy).interactiveDismissDisabled(busy)
            .onDisappear { password = ""; confirmation = "" }
            .alert(copy.text(registering ? "cloud.registrationFailed" : "cloud.loginFailed"), isPresented: $showAuthError) {
                Button(copy.text("settingsClose"), role: .cancel) { }
            } message: {
                Text(copy.text(errorKey ?? "cloud.invalid"))
            }
    }
    private var authenticationForm: some View {
        CafePanel {
            VStack(alignment: .leading, spacing: 17) {
                Picker(copy.text("settings.account"), selection: $registering) {
                    Text(copy.text("settings.login")).tag(false)
                    Text(copy.text("settings.register")).tag(true)
                }.pickerStyle(.segmented).onChange(of: registering) { _ in errorKey = nil; password = ""; confirmation = "" }
                if registering {
                    SettingsNote(key: "cloud.registrationHint")
                    SettingsInput(key: "settings.fullName", text: $name)
                }
                SettingsInput(key: "settings.email", text: $email, keyboard: .emailAddress)
                SettingsInput(key: "settings.password", text: $password, secure: true)
                if registering {
                    SettingsInput(key: "settings.confirmPassword", text: $confirmation, secure: true)
                        .submitLabel(.go).onSubmit { submit() }
                    SettingsNote(key: "settings.passwordHint")
                }
                SettingsError(key: errorKey)
                Button { submit() } label: {
                    HStack {
                        if busy { ProgressView().tint(CafePalette.surface) }
                        Text(copy.text(busy ? (registering ? "cloud.registering" : "cloud.signingIn") : (registering ? "settings.register" : "settings.login")))
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(CafePrimaryButton()).disabled(busy).opacity(busy ? 0.7 : 1)
                if !registering { NavigationLink(copy.text("cloud.forgotPassword")) { RecoveryView() } }
            }
        }
    }
    private var validationError: String? {
        if registering && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "cloud.nameRequired" }
        let mail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !AccountStore.validEmail(mail) { return "cloud.emailInvalid" }
        if password.isEmpty { return "cloud.passwordRequired" }
        if registering && !AccountStore.validPassword(password) { return "cloud.passwordTooShort" }
        if registering && password != confirmation { return "cloud.passwordMismatch" }
        return nil
    }
    private func signOut() {
        guard !busy else { return }
        busy = true; errorKey = nil
        Task { @MainActor in
            do { try await accounts.logout(); password = ""; confirmation = "" }
            catch { errorKey = settingsErrorKey(error) }
            busy = false
        }
    }
    private func submit() {
        guard !busy, !accounts.restoring else { return }
        if let validationError = validationError {
            errorKey = validationError
            showAuthError = true
            return
        }
        busy = true; errorKey = nil
        Task { @MainActor in
            do {
                try await accounts.authenticate(name: name, email: email, password: password, registering: registering)
                password = ""
                confirmation = ""
            } catch {
                errorKey = settingsErrorKey(error)
                showAuthError = true
            }
            // Xcode 14.2: update view state directly, outside a defer block.
            busy = false
        }
    }
}

@MainActor
private struct ManageAccountView: View {
    @Environment(\.copy) private var copy
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var accounts = AccountStore.shared
    @State private var name = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var errorKey: String?
    @State private var saved = false
    @State private var busy = false
    var body: some View {
        SettingsPage(title: "settings.manage") {
            CafePanel {
                VStack(alignment: .leading, spacing: 15) {
                    SettingsInput(key: "settings.fullName", text: $name)
                    Button(copy.text("settings.save")) {
                        busy = true
                        Task { @MainActor in
                            do { try await accounts.rename(name); saved = true; errorKey = nil }
                            catch { errorKey = settingsErrorKey(error) }
                            busy = false
                        }
                    }.buttonStyle(CafePrimaryButton())
                }
            }
            passwordSection
            SettingsError(key: errorKey)
            if saved { SettingsNote(key: "settings.saved") }
        }.disabled(busy).navigationBarBackButtonHidden(busy).interactiveDismissDisabled(busy)
            .onAppear { name = accounts.account?.name ?? "" }
            .onDisappear { password = ""; newPassword = ""; confirmation = "" }
    }
    private var passwordSection: some View {
        CafePanel {
            VStack(alignment: .leading, spacing: 15) {
                Text(copy.text("settings.changePassword")).font(.headline)
                SettingsInput(key: "settings.currentPassword", text: $password, secure: true)
                SettingsInput(key: "settings.newPassword", text: $newPassword, secure: true)
                SettingsInput(key: "settings.confirmPassword", text: $confirmation, secure: true)
                SettingsNote(key: "settings.passwordHint")
                Button { performPasswordChange() } label: {
                    HStack { if busy { ProgressView() }; Text(copy.text("settings.changePassword")) }
                }.buttonStyle(CafePrimaryButton())
                    .disabled(password.isEmpty || !AccountStore.validPassword(newPassword) || newPassword != confirmation)
            }
        }
    }
    private func performPasswordChange() {
        guard !busy else { return }
        busy = true; saved = false; errorKey = nil
        Task { @MainActor in
            do {
                try await accounts.changePassword(current: password, new: newPassword)
                saved = true
            } catch { errorKey = settingsErrorKey(error) }
            // Run cleanup after success or failure, before dismissing the view.
            password = ""
            newPassword = ""
            confirmation = ""
            busy = false
        }
    }
}

@MainActor
struct AccountSettingsView: View {
    var body: some View { SettingsPage(title: "profile") { ProfileAccountSection() } }
}

@MainActor
private struct RecoveryView: View {
    @Environment(\.copy) private var copy
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var sent = false
    @State private var done = false
    @State private var busy = false
    @State private var errorKey: String?
    var body: some View {
        SettingsPage(title: "cloud.forgotPassword") {
            CafePanel {
                VStack(spacing: 16) {
                    SettingsInput(key: "settings.email", text: $email, keyboard: .emailAddress)
                    if sent {
                        SettingsInput(key: "cloud.otp", text: $code, keyboard: .numberPad)
                        SettingsInput(key: "settings.newPassword", text: $password, secure: true)
                        SettingsInput(key: "settings.confirmPassword", text: $confirmation, secure: true)
                        SettingsNote(key: "settings.passwordHint")
                    }
                    SettingsError(key: errorKey)
                    if done { SettingsNote(key: "cloud.passwordReset") }
                    else {
                        Button(copy.text(sent ? "cloud.resetPassword" : "cloud.sendCode")) { submit() }
                            .buttonStyle(CafePrimaryButton())
                            .disabled(!AccountStore.validEmail(email) || busy || (sent && (code.isEmpty || !AccountStore.validPassword(password) || password != confirmation)))
                    }
                    if sent { SettingsNote(key: "cloud.codeSent") }
                }
            }
        }.disabled(busy).interactiveDismissDisabled(busy).navigationBarBackButtonHidden(busy)
            .onDisappear { password = ""; confirmation = ""; code = "" }
    }
    private func submit() {
        busy = true; errorKey = nil
        Task { @MainActor in
            do {
                if sent { try await AccountStore.shared.resetPassword(email: email, otp: code, password: password); done = true }
                else { try await AccountStore.shared.requestRecovery(email: email); sent = true }
            } catch { errorKey = settingsErrorKey(error) }
            password = ""; confirmation = ""; busy = false
        }
    }
}
