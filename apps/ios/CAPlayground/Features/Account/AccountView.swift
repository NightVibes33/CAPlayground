import SwiftUI

struct AccountView: View {
    private enum Mode { case view, email, username, password }

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .view
    @State private var newEmail = ""
    @State private var username = ""
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Button { dismiss() } label: { Label("Back", systemImage: "arrow.left") }
                Text("Manage Account").font(.system(size: 36, weight: .bold))
                Text("Update your account settings and linked providers").foregroundStyle(.secondary)
                if let message = auth.message { Text(message).font(.subheadline).foregroundStyle(.green) }
                if let error = auth.error { Text(error).font(.subheadline).foregroundStyle(.red) }
                content
            }
            .padding(24).frame(maxWidth: 672).frame(maxWidth: .infinity)
        }
        .navigationBarBackButtonHidden()
        .onAppear { username = auth.username }
        .confirmationDialog("This will delete your account permanently. Continue?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Account", role: .destructive) { Task { if await auth.deleteAccount() { dismiss() } } }
            Button("Cancel", role: .cancel) { }
        }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .view: accountCards
        case .email: updateEmailCard
        case .username: usernameCard
        case .password: passwordCard
        }
    }

    private var accountCards: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("Account Information").font(.title3.bold()); Spacer(); Button("Sign out") { Task { await auth.signOut(); dismiss() } }.buttonStyle(.bordered) }
                labeledValue("Email", auth.user?.email ?? "(loading)")
                labeledValue("Username", auth.username.isEmpty ? "Not set" : auth.username)
            }.padding(24).caPanel()

            VStack(alignment: .leading, spacing: 16) {
                Text("Linked Accounts").font(.title3.bold())
                Text("Sign in with any of these providers to access your account.").font(.subheadline).foregroundStyle(.secondary)
                Text("Currently Linked").font(.subheadline.weight(.medium))
                if (auth.user?.identities ?? []).isEmpty {
                    Text("No linked accounts found.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(auth.user?.identities ?? []) { identity in
                        HStack {
                            Image(systemName: providerSymbol(identity.provider)).frame(width: 32)
                            VStack(alignment: .leading) {
                                Text(identity.provider.capitalized).font(.subheadline.weight(.medium))
                                Text(identity.email ?? "No email").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(12).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator)))
                    }
                }
            }.padding(24).caPanel()

            VStack(alignment: .leading, spacing: 12) {
                Text("Account Actions").font(.title3.bold())
                Button("Update Email") { resetMessages(); mode = .email }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Change Username") { resetMessages(); username = auth.username; mode = .username }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Change Password") { resetMessages(); mode = .password }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button("Delete Account", role: .destructive) { confirmingDelete = true }.buttonStyle(.borderedProminent).tint(CATheme.destructive).frame(maxWidth: .infinity)
            }.padding(24).caPanel()
        }
    }

    private var updateEmailCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Update Email").font(.title3.bold())
            Text("Current Email").font(.subheadline.weight(.medium))
            Text(auth.user?.email ?? "").foregroundStyle(.secondary)
            Text("New Email").font(.subheadline.weight(.medium))
            TextField("you@example.com", text: $newEmail).textInputAutocapitalization(.never).keyboardType(.emailAddress).textFieldStyle(.roundedBorder)
            HStack {
                Button("Send Verification & Sign Out") { Task { if await auth.updateEmail(newEmail) { dismiss() } } }.buttonStyle(.borderedProminent)
                Button("Back") { mode = .view }
            }
            Text("We’ll email a verification link to your new address. After confirming, sign back in.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).caPanel()
    }

    private var usernameCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Username").font(.title3.bold())
            Text("Username").font(.subheadline.weight(.medium))
            TextField("Pick a username", text: $username).textFieldStyle(.roundedBorder)
            HStack {
                Button("Save Username") { Task { await auth.saveUsername(username); mode = .view } }.buttonStyle(.borderedProminent)
                Button("Back") { mode = .view }
            }
        }.padding(24).caPanel()
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Password").font(.title3.bold())
            Text("For security, password changes are done via email. We’ll send a reset link to your current address.").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Send Reset Email") { Task { await auth.sendPasswordReset(email: auth.user?.email ?? "") } }.buttonStyle(.borderedProminent)
                Button("Back") { mode = .view }
            }
        }.padding(24).caPanel()
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.subheadline.weight(.medium)); Text(value).font(.subheadline).foregroundStyle(.secondary) }
    }

    private func providerSymbol(_ provider: String) -> String {
        switch provider {
        case "github": "chevron.left.forwardslash.chevron.right"
        case "discord": "bubble.left.and.bubble.right"
        case "google": "g.circle"
        default: "envelope"
        }
    }

    private func resetMessages() { auth.message = nil; auth.error = nil }
}
