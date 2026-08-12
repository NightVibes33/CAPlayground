import Foundation
import SwiftUI

private struct GitHubContributor: Codable, Identifiable, Sendable {
    let id: Int
    let login: String
    let avatarURL: URL
    let htmlURL: URL
    let contributions: Int

    enum CodingKeys: String, CodingKey {
        case id, login, contributions
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
    }
}

struct ContributorsView: View {
    @State private var contributors: [GitHubContributor] = []
    @State private var isLoading = true
    @State private var failed = false

    private var totalContributions: Int {
        contributors.reduce(0) { $0 + $1.contributions }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 48) {
                header

                if isLoading {
                    ProgressView()
                        .controlSize(.large)
                        .frame(minHeight: 200)
                } else if failed || contributors.isEmpty {
                    errorState
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 24)], spacing: 24) {
                        ForEach(contributors) { contributor in
                            Link(destination: contributor.htmlURL) {
                                contributorCard(contributor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                callToAction
            }
            .frame(maxWidth: 1152)
            .padding(.horizontal, 24)
            .padding(.vertical, 64)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Contributors")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadContributors() }
    }

    private var header: some View {
        VStack(spacing: 24) {
            Label("Open Source", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CATheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(CATheme.accent.opacity(0.1), in: Capsule())
                .overlay(Capsule().stroke(CATheme.accent.opacity(0.2)))

            Text("Contributors")
                .font(.system(size: 52, weight: .bold))

            Text("Meet the amazing developers who are building an amazing Core Animation editor for the community to make stunning wallpapers")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 760)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 32) { statistics }
                VStack(spacing: 20) { statistics }
            }
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private var statistics: some View {
        stat(value: contributors.count, label: "Contributors", symbol: "person.2.fill")
        stat(value: totalContributions, label: "Contributions", symbol: "point.3.connected.trianglepath.dotted")
    }

    private func stat(value: Int, label: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(CATheme.accent)
                .frame(width: 48, height: 48)
                .background(CATheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(value.formatted()).font(.title2.bold())
                Text(label).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func contributorCard(_ contributor: GitHubContributor) -> some View {
        VStack(spacing: 16) {
            AsyncImage(url: contributor.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 80, height: 80)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 2))

            Text("@\(contributor.login)")
                .font(.title3.weight(.semibold))

            Label("\(contributor.contributions) contributions", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.secondary.opacity(0.1), in: Capsule())
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 230)
        .caPanel()
    }

    private var errorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Unable to load contributors").font(.title3.bold())
            Text("Couldn't fetch contributor data from GitHub. Please try again later.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("View on GitHub", destination: URL(string: "https://github.com/CAPlayground/CAPlayground/graphs/contributors")!)
                .buttonStyle(.borderedProminent)
                .tint(CATheme.accent)
        }
        .frame(minHeight: 240)
    }

    private var callToAction: some View {
        VStack(spacing: 16) {
            Text("Want to contribute?").font(.title2.bold())
            Text("CAPlayground is open source and welcomes contributions from developers around the world. Join our community and help build the future of animated wallpapers.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 680)
            Link(destination: URL(string: "https://github.com/CAPlayground/CAPlayground")!) {
                Label("View on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.borderedProminent)
            .tint(CATheme.accent)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func loadContributors() async {
        guard let url = URL(string: "https://api.github.com/repos/CAPlayground/CAPlayground/contributors") else { return }
        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            contributors = try JSONDecoder().decode([GitHubContributor].self, from: data)
            failed = false
        } catch {
            failed = true
        }
        isLoading = false
    }
}
