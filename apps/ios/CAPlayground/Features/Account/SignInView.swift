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
        .onChange(of: auth.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
        .navigationDestination(isPresented: $showTerms) { TermsOfServiceView() }
        .navigationDestination(isPresented: $showPrivacy) { PrivacyPolicyView() }
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
        Button { auth.signIn(provider: provider) } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity)
        }.buttonStyle(CAWebButtonStyle(variant: .outline)).disabled(auth.isLoading)
    }

    private func toggleTheme() {
        appearance = colorScheme == .dark ? "light" : "dark"
    }

    private func clearMessages() { auth.error = nil; auth.message = nil }
}
