import SwiftUI
import UIKit

struct SignInView: View {
    private enum Mode { case signIn, signUp, forgotPassword }

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance") private var appearance = "system"
    @State private var mode: Mode = .signIn
    @State private var emailOrUsername = ""
    @State private var email = ""
    @State private var signupUsername = ""
    @State private var password = ""
    @State private var showTerms = false
    @State private var showPrivacy = false
    @State private var oauthProvider: String?
    @State private var showAuthSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    if mode != .forgotPassword {
                        Button { dismiss() } label: { Label("Back", systemImage: "arrow.left") }
                            .buttonStyle(.plain)
                    }
                    Spacer()
                    Button { toggleTheme() } label: {
                        Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                            .font(.system(size: 18))
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Toggle theme")
                }
                card
                    .frame(maxWidth: 448)
                    .frame(maxWidth: .infinity)
            }
            .padding(16)
            .padding(.top, 8)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            if oauthProvider != nil {
                showAuthSuccess = true
            } else {
                dismiss()
            }
        }
        .onChange(of: auth.error) { _, error in
            if error != nil && !auth.isSignedIn { oauthProvider = nil }
        }
        .onChange(of: auth.isLoading) { _, loading in
            if !loading && !auth.isSignedIn && auth.error == nil { oauthProvider = nil }
        }
        .navigationDestination(isPresented: $showTerms) { TermsOfServiceView() }
        .navigationDestination(isPresented: $showPrivacy) { PrivacyPolicyView() }
        .fullScreenCover(isPresented: $showAuthSuccess) {
            NavigationStack {
                WebsiteAuthSuccessView(providerHint: oauthProvider) {
                    showAuthSuccess = false
                    oauthProvider = nil
                    dismiss()
                } onBackToSignIn: {
                    showAuthSuccess = false
                    oauthProvider = nil
                }
            }
        }
    }

    private var card: some View {
        VStack(spacing: 20) {
            Text(title).font(.system(size: 36, weight: .bold)).multilineTextAlignment(.center)

            switch mode {
            case .signIn: signInForm
            case .signUp: signUpForm
            case .forgotPassword: forgotPasswordForm
            }
        }
        .padding(24)
        .caPanel()
    }

    private var title: String {
        switch mode {
        case .signIn: "Welcome Back"
        case .signUp: "Create an Account"
        case .forgotPassword: "Reset your password"
        }
    }

    private var signInForm: some View {
        VStack(spacing: 20) {
            field("Email", placeholder: "Your Email", icon: "at", text: $emailOrUsername, contentType: .emailAddress)
            VStack(alignment: .trailing, spacing: 8) {
                secureField("Password", placeholder: "Your Password", text: $password)
                Button("Forgot password?") { clearMessages(); mode = .forgotPassword }
                    .font(.subheadline).foregroundStyle(CATheme.accent)
            }
            messages
            Button {
                oauthProvider = nil
                Task { _ = await auth.signIn(email: emailOrUsername, password: password) }
            } label: {
                Text(auth.isLoading ? "Signing In..." : "Sign In").frame(maxWidth: .infinity)
            }
            .buttonStyle(CAWebButtonStyle(variant: .accent)).disabled(auth.isLoading)
            separator
            providerButton("Continue with Google", provider: "google", symbol: "g.circle")
            providerButton("Continue with GitHub", provider: "github", symbol: "chevron.left.forwardslash.chevron.right")
            providerButton("Continue with Discord", provider: "discord", symbol: "bubble.left.and.bubble.right")
            HStack(spacing: 4) {
                Text("New here?").foregroundStyle(.secondary)
                Button("Create an account") { clearMessages(); mode = .signUp }.foregroundStyle(CATheme.accent)
            }.font(.subheadline)
        }
    }

    private var signUpForm: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                field("Username", placeholder: "Choose a username", icon: "person", text: $signupUsername)
                Text("3–20 chars. Letters, numbers, and ! - _ . only.").font(.caption).foregroundStyle(.secondary)
            }
            field("Email", placeholder: "Your Email", icon: "at", text: $email, contentType: .emailAddress)
            secureField("Password", placeholder: "Create a Password", text: $password)
            messages
            legalAgreement
            Button {
                oauthProvider = nil
                Task {
                    if await auth.signUp(username: signupUsername, email: email, password: password) { mode = .signIn }
                }
            } label: { Text(auth.isLoading ? "Signing Up..." : "Sign Up").frame(maxWidth: .infinity) }
                .buttonStyle(CAWebButtonStyle(variant: .accent)).disabled(auth.isLoading)
            separator
            providerButton("Sign up with Google", provider: "google", symbol: "g.circle")
            providerButton("Sign up with GitHub", provider: "github", symbol: "chevron.left.forwardslash.chevron.right")
            providerButton("Sign up with Discord", provider: "discord", symbol: "bubble.left.and.bubble.right")
            HStack(spacing: 4) {
                Text("Already have an account?").foregroundStyle(.secondary)
                Button("Sign in") { clearMessages(); mode = .signIn }.foregroundStyle(CATheme.accent)
            }.font(.subheadline)
        }
    }

    private var legalAgreement: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("By signing up, you agree to our")
            HStack(spacing: 4) {
                Button("Terms of Service") { showTerms = true }.underline()
                Text("and")
                Button("Privacy Policy") { showPrivacy = true }.underline()
                Text(".")
            }
            Text("You must be at least 13 years old, or the minimum age of digital consent in your country.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var forgotPasswordForm: some View {
        VStack(spacing: 20) {
            field("Email", placeholder: "you@example.com", icon: "at", text: $email, contentType: .emailAddress)
            messages
            Button {
                Task { await auth.sendPasswordReset(email: email) }
            } label: { Text(auth.isLoading ? "Sending..." : "Send reset link").frame(maxWidth: .infinity) }
                .buttonStyle(CAWebButtonStyle(variant: .accent)).disabled(auth.isLoading)
            HStack(spacing: 4) {
                Text("Remembered your password?").foregroundStyle(.secondary)
                Button("Back to sign in") { clearMessages(); mode = .signIn }.foregroundStyle(CATheme.accent)
            }.font(.subheadline)
        }
    }

    @ViewBuilder private var messages: some View {
        if let error = auth.error { Text(error).font(.subheadline).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading) }
        if let message = auth.message { Text(message).font(.subheadline).foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .leading) }
    }

    private var separator: some View {
        HStack(spacing: 12) { Divider(); Text("or").font(.caption).foregroundStyle(.secondary); Divider() }
    }

    private func field(_ label: String, placeholder: String, icon: String, text: Binding<String>, contentType: UITextContentType? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.medium))
            HStack { Image(systemName: icon).foregroundStyle(.secondary); TextField(placeholder, text: text).textInputAutocapitalization(.never).textContentType(contentType) }
                .padding(.horizontal, 12).frame(height: 42).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
        }
    }

    private func secureField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.medium))
            HStack { Image(systemName: "lock").foregroundStyle(.secondary); SecureField(placeholder, text: text).textContentType(.password) }
                .padding(.horizontal, 12).frame(height: 42).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
        }
    }

    private func providerButton(_ title: String, provider: String, symbol: String) -> some View {
        Button {
            oauthProvider = provider
            auth.signIn(provider: provider)
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }.buttonStyle(CAWebButtonStyle(variant: .outline)).disabled(auth.isLoading)
    }

    private func toggleTheme() {
        appearance = colorScheme == .dark ? "light" : "dark"
    }

    private func clearMessages() { auth.error = nil; auth.message = nil }
}

private struct WebsiteAuthSuccessView: View {
    private enum Status { case checking, needUsername, ready, notSignedIn }

    @Environment(AuthStore.self) private var auth
    let providerHint: String?
    let onContinue: () -> Void
    let onBackToSignIn: () -> Void

    @State private var status: Status = .checking
    @State private var username = ""
    @State private var profileUsername = ""
    @State private var provider = "email"
    @State private var accountEmail = ""
    @State private var saving = false
    @State private var localError: String?

    var body: some View {
        ScrollView {
            VStack {
                Group {
                    if status == .checking {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Completing sign-in…").font(.title2.bold())
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Verifying session").foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        VStack(spacing: 18) {
                            Text(title)
                                .font(.system(size: status == .ready ? 30 : 28, weight: .bold))
                                .multilineTextAlignment(.center)
                            content
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 448)
                .caPanel()
            }
            .frame(maxWidth: .infinity, minHeight: 700)
            .padding(16)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await checkSession() }
    }

    private var title: String {
        switch status {
        case .checking: "Completing sign-in…"
        case .needUsername: "Choose a username"
        case .ready: "You're signed in"
        case .notSignedIn: "Sign-in failed or expired"
        }
    }

    @ViewBuilder private var content: some View {
        switch status {
        case .checking:
            EmptyView()
        case .needUsername:
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Username").font(.subheadline.weight(.medium))
                    TextField("Pick a username", text: $username)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                    Text("3–20 chars. Letters, numbers, and ! - _ . only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let localError { Text(localError).font(.subheadline).foregroundStyle(.red) }
                Button {
                    saveUsername()
                } label: {
                    Text(saving ? "Saving…" : "Save username").frame(maxWidth: .infinity)
                }
                .buttonStyle(CAWebButtonStyle(variant: .accent))
                .disabled(saving)
            }
        case .ready:
            VStack(spacing: 14) {
                HStack(spacing: 16) {
                    Image(systemName: providerSymbol)
                        .font(.system(size: 27))
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color(.separator), lineWidth: 2))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profileUsername.isEmpty ? "(no username)" : profileUsername)
                            .font(.headline)
                        Text(accountEmail.isEmpty ? "(no email)" : accountEmail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))

                Button("Continue") { onContinue() }
                    .buttonStyle(CAWebButtonStyle(variant: .accent))
                    .frame(maxWidth: .infinity)
                NavigationLink("Create a Project") { ProjectsView() }
                    .buttonStyle(CAWebButtonStyle(variant: .outline))
                    .frame(maxWidth: .infinity)
                NavigationLink("Account Dashboard") { DashboardView() }
                    .buttonStyle(CAWebButtonStyle(variant: .outline))
                    .frame(maxWidth: .infinity)
                Button("Sign out", role: .destructive) {
                    Task {
                        await auth.signOut()
                        onBackToSignIn()
                    }
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(CATheme.destructive, in: RoundedRectangle(cornerRadius: 8))
            }
        case .notSignedIn:
            VStack(spacing: 16) {
                Text("Please try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Back to sign in") { onBackToSignIn() }
                    .buttonStyle(CAWebButtonStyle(variant: .outline))
            }
        }
    }

    private var providerSymbol: String {
        switch provider.lowercased() {
        case "google": "g.circle"
        case "github": "chevron.left.forwardslash.chevron.right"
        case "discord": "bubble.left.and.bubble.right"
        default: "envelope"
        }
    }

    private func checkSession() async {
        await auth.refreshUser()
        guard let user = auth.user else {
            status = .notSignedIn
            return
        }

        accountEmail = user.email ?? ""
        provider = providerHint ?? string(user.appMetadata?["provider"]) ?? user.identities?.first?.provider ?? "email"
        if !auth.username.isEmpty {
            profileUsername = auth.username
            status = .ready
        } else {
            username = suggestedUsername(from: user)
            status = .needUsername
        }
    }

    private func saveUsername() {
        localError = nil
        guard username.range(of: "^[A-Za-z0-9!._-]{3,20}$", options: .regularExpression) != nil else {
            localError = "Username must be 3-20 chars and only letters, numbers, and ! - _ ."
            return
        }
        saving = true
        Task {
            auth.error = nil
            await auth.saveUsername(username)
            saving = false
            if let error = auth.error {
                localError = error
            } else {
                profileUsername = username
                status = .ready
            }
        }
    }

    private func suggestedUsername(from user: AuthUser) -> String {
        var candidates: [String] = []
        let meta = user.userMetadata ?? [:]
        for key in ["user_name", "preferred_username", "name", "full_name"] {
            if let value = string(meta[key]) { candidates.append(value) }
        }
        for identity in user.identities ?? [] {
            for key in ["user_name", "login", "username", "global_name"] {
                if let value = string(identity.identityData?[key]) { candidates.append(value) }
            }
        }
        for raw in candidates {
            let clean = String(raw.filter { $0.isLetter || $0.isNumber || "!._-".contains($0) }.prefix(20))
            if clean.range(of: "^[A-Za-z0-9!._-]{3,20}$", options: .regularExpression) != nil { return clean }
        }
        return ""
    }

    private func string(_ value: JSONValue?) -> String? {
        guard case .string(let text) = value else { return nil }
        return text
    }
}

struct WebsiteResetPasswordView: View {
    @Environment(AuthStore.self) private var auth
    @State private var password = ""
    @State private var confirmation = ""
    @State private var checking = true
    @State private var updating = false
    @State private var localError: String?
    @State private var successMessage: String?

    var body: some View {
        ScrollView {
            VStack {
                VStack(spacing: 20) {
                    Text("Set a new password")
                        .font(.system(size: 36, weight: .bold))
                        .multilineTextAlignment(.center)

                    if checking {
                        Text("Verifying your reset link...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if auth.user != nil {
                        passwordField("New Password", placeholder: "Create a new password", text: $password)
                        passwordField("Confirm Password", placeholder: "Re-enter your password", text: $confirmation)

                        if let localError {
                            Text(localError).font(.subheadline).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let successMessage {
                            Text(successMessage).font(.subheadline).foregroundStyle(.green).frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            updatePassword()
                        } label: {
                            Text(updating ? "Updating..." : "Update password").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(CAWebButtonStyle(variant: .accent))
                        .disabled(updating)

                        Button("Back to sign in") { auth.requiresPasswordReset = false }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(CATheme.accent)
                    } else {
                        Text("Verifying your reset link...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 448)
                .caPanel()
            }
            .frame(maxWidth: .infinity, minHeight: 650)
            .padding(16)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .interactiveDismissDisabled()
        .task {
            await auth.refreshUser()
            checking = false
        }
    }

    private func passwordField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.medium))
            HStack {
                Image(systemName: "lock").foregroundStyle(.secondary)
                SecureField(placeholder, text: text).textContentType(.newPassword)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
        }
    }

    private func updatePassword() {
        localError = nil
        successMessage = nil
        guard password.count >= 8 else {
            localError = "Password must be at least 8 characters"
            return
        }
        guard password == confirmation else {
            localError = "Passwords do not match"
            return
        }
        updating = true
        Task {
            auth.error = nil
            if await auth.updatePassword(password) {
                // Keep the native reset surface open after a successful update so it mirrors
                // the website's success state instead of disappearing immediately.
                auth.requiresPasswordReset = true
                successMessage = "Password updated. You can now continue to the app."
            } else {
                localError = auth.error ?? "Failed to update password"
            }
            updating = false
        }
    }
}
