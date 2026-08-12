import SwiftUI

struct AccountView: View {
    private enum Mode { case view, email, username, password }

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var mode: Mode = .view
    @State private var newEmail = ""
    @State private var username = ""
    @State private var confirmingDelete = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Manage Account").font(.system(size: 36, weight: .bold))
                        Text("Update your account settings and linked providers").foregroundStyle(.secondary)
                    }
                    if let message = auth.message { Text(message).font(.subheadline).foregroundStyle(.green) }
                    if let error = auth.error { Text(error).font(.subheadline).foregroundStyle(.red) }
                    content
                }
                .frame(maxWidth: 672, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 72)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity)
            }
            .background(CATheme.background(scheme).ignoresSafeArea())

            Button { dismiss() } label: { Label("Back", systemImage: "arrow.left") }
                .buttonStyle(CAWebButtonStyle(variant: .ghost, height: 32))
                .padding(.leading, 12).padding(.top, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
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
                HStack {
                    Text("Account Information").font(.title3.bold())
                    Spacer()
                    Button("Sign out") { Task { await auth.signOut(); dismiss() } }.buttonStyle(CAWebButtonStyle(variant: .outline))
                }
                labeledValue("Email", auth.user?.email ?? "(loading)")
                labeledValue("Username", auth.username.isEmpty ? "Not set" : auth.username)
            }.padding(24).websiteCard(scheme)

            VStack(alignment: .leading, spacing: 16) {
                Text("Linked Accounts").font(.title3.bold())
                Text("Sign in with any of these providers to access your account.").font(.subheadline).foregroundStyle(.secondary)
                Text("Currently Linked").font(.subheadline.weight(.medium))
                if (auth.user?.identities ?? []).isEmpty {
                    Text("No linked accounts found.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(auth.user?.identities ?? []) { identity in
                        HStack(spacing: 12) {
                            Image(systemName: providerSymbol(identity.provider)).frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(identity.provider.capitalized).font(.subheadline.weight(.medium))
                                Text(identity.email ?? "No email").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }.padding(12).overlay(RoundedRectangle(cornerRadius: 8).stroke(CATheme.border(scheme)))
                    }
                }
            }.padding(24).websiteCard(scheme)

            VStack(alignment: .leading, spacing: 12) {
                Text("Account Actions").font(.title3.bold())
                Button("Update Email") { resetMessages(); newEmail = ""; mode = .email }.buttonStyle(CAWebButtonStyle(variant: .outline)).frame(maxWidth: .infinity)
                Button("Change Username") { resetMessages(); username = auth.username; mode = .username }.buttonStyle(CAWebButtonStyle(variant: .outline)).frame(maxWidth: .infinity)
                Button("Change Password") { resetMessages(); mode = .password }.buttonStyle(CAWebButtonStyle(variant: .outline)).frame(maxWidth: .infinity)
                Button("Delete Account", role: .destructive) { confirmingDelete = true }
                    .font(.body.weight(.semibold)).foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 40).background(CATheme.destructive, in: RoundedRectangle(cornerRadius: 8))
            }.padding(24).websiteCard(scheme)
        }
    }

    private var updateEmailCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Update Email").font(.title3.bold())
            Text("Current Email").font(.subheadline.weight(.medium))
            Text(auth.user?.email ?? "").foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading).overlay(RoundedRectangle(cornerRadius: 8).stroke(CATheme.border(scheme)))
            Text("New Email").font(.subheadline.weight(.medium))
            TextField("you@example.com", text: $newEmail).textInputAutocapitalization(.never).keyboardType(.emailAddress).textFieldStyle(.roundedBorder)
            ViewThatFits(in: .horizontal) {
                HStack { updateEmailActions }
                VStack(alignment: .leading, spacing: 8) { updateEmailActions }
            }
            Text("We’ll email a verification link to your new address. After confirming, sign back in.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).websiteCard(scheme)
    }

    @ViewBuilder private var updateEmailActions: some View {
        Button("Send Verification & Sign Out") { Task { if await auth.updateEmail(newEmail) { dismiss() } } }.buttonStyle(CAWebButtonStyle(variant: .accent))
        Button("Back") { mode = .view }.buttonStyle(CAWebButtonStyle(variant: .ghost))
    }

    private var usernameCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Username").font(.title3.bold())
            Text("Username").font(.subheadline.weight(.medium))
            TextField("Pick a username", text: $username).textFieldStyle(.roundedBorder)
            HStack {
                Button("Save Username") { Task { await auth.saveUsername(username); mode = .view } }.buttonStyle(CAWebButtonStyle(variant: .accent))
                Button("Back") { mode = .view }.buttonStyle(CAWebButtonStyle(variant: .ghost))
            }
        }.padding(24).websiteCard(scheme)
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Change Password").font(.title3.bold())
            Text("For security, password changes are done via email. We’ll send a reset link to your current address.").font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Send Reset Email") { Task { await auth.sendPasswordReset(email: auth.user?.email ?? "") } }.buttonStyle(CAWebButtonStyle(variant: .accent))
                Button("Back") { mode = .view }.buttonStyle(CAWebButtonStyle(variant: .ghost))
            }
        }.padding(24).websiteCard(scheme)
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(label).font(.subheadline.weight(.medium)); Text(value).font(.subheadline).foregroundStyle(.secondary) }
    }

    private func providerSymbol(_ provider: String) -> String {
        switch provider { case "github": "chevron.left.forwardslash.chevron.right"; case "discord": "bubble.left.and.bubble.right"; case "google": "g.circle"; default: "envelope" }
    }

    private func resetMessages() { auth.message = nil; auth.error = nil }
}

private extension View {
    func websiteCard(_ scheme: ColorScheme) -> some View {
        self.background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(CATheme.border(scheme).opacity(0.8), lineWidth: 1) }
    }
}
