from pathlib import Path

# Privacy / Terms: match the website's standalone legal-document shell.
p = Path("apps/ios/CAPlayground/Features/Legal/LegalViews.swift")
s = p.read_text()
end = s.index("private let privacySections = [")
head = '''import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        LegalDocumentView(kind: .privacy, title: "Privacy Policy", updated: "20th October 2025", sections: privacySections)
    }
}

struct TermsOfServiceView: View {
    var body: some View {
        LegalDocumentView(kind: .terms, title: "Terms of Service", updated: "9th December 2025", sections: termsSections)
    }
}

private struct LegalSection: Identifiable {
    let id = UUID()
    let title: String
    let body: String
}

private enum LegalKind {
    case privacy
    case terms
}

private struct LegalDocumentView: View {
    @Environment(\\.colorScheme) private var scheme
    @Environment(\\.horizontalSizeClass) private var sizeClass
    @Environment(\\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance = "system"

    let kind: LegalKind
    let title: String
    let updated: String
    let sections: [LegalSection]

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [CATheme.muted(scheme).opacity(0.45), CATheme.background(scheme)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    legalToolbar
                    VStack(alignment: .leading, spacing: 28) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(.system(size: sizeClass == .compact ? 36 : 48, weight: .bold))
                            Text("Last Updated: \\(updated)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(section.title).font(.title2.bold())
                                if section.title.hasSuffix("Contact") {
                                    contactSection
                                } else {
                                    Text(attributedBody(section))
                                        .textSelection(.enabled)
                                        .lineSpacing(5)
                                }
                            }
                        }
                    }
                    .padding(sizeClass == .compact ? 20 : 40)
                    .frame(maxWidth: 768, alignment: .leading)
                    .background(CATheme.background(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(CATheme.border(scheme), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
                }
                .frame(maxWidth: 896)
                .padding(.horizontal, sizeClass == .compact ? 16 : 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var legalToolbar: some View {
        HStack {
            Button { dismiss() } label: { Label("Back", systemImage: "arrow.left") }
                .buttonStyle(CAWebButtonStyle(variant: .ghost))
            Spacer()
            Button { appearance = scheme == .dark ? "light" : "dark" } label: {
                Image(systemName: scheme == .dark ? "sun.max" : "moon")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(CAWebButtonStyle(variant: .outline, height: 36))
            .accessibilityLabel("Toggle theme")
        }
        .frame(maxWidth: 768)
    }

    private func attributedBody(_ section: LegalSection) -> AttributedString {
        var body = section.body
        if kind == .privacy && section.title == "4. Third Parties" {
            body = body.replacingOccurrences(
                of: "Google's Privacy Policy",
                with: "[Google's Privacy Policy](https://policies.google.com/privacy)"
            )
        }
        return (try? AttributedString(markdown: body)) ?? AttributedString(body)
    }

    @ViewBuilder
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Questions? Contact us at").lineSpacing(5)
            Link("support@enkei64.xyz", destination: URL(string: "mailto:support@enkei64.xyz")!)
            if kind == .privacy {
                NavigationLink("Terms of Service") { TermsOfServiceView() }
            } else {
                NavigationLink("Privacy Policy") { PrivacyPolicyView() }
            }
        }
        .font(.body)
    }
}

'''
s = head + s[end:]
p.write_text(s)

# Home: match the website's responsive 4-col / 3-col+wide / 2-col / 1-col bento composition.
p = Path("apps/ios/CAPlayground/Features/Home/HomeView.swift")
s = p.read_text()
start = s.index("    private var layersSection: some View {")
end = s.index("    private var growingSection: some View {", start)
section = r'''    private var layersSection: some View {
        VStack(spacing: 48) {
            VStack(spacing: 16) {
                Text("Layers of Possibility.")
                    .font(.system(size: horizontalSizeClass == .compact ? 40 : 60, weight: .bold))
                Text("Build complex wallpaper states by combining different layer types, each with their own unique properties and animations.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 680)
            }

            ViewThatFits(in: .horizontal) {
                VStack(spacing: 16) {
                    bentoRow([0, 1, 2, 3], height: 400, minimumWidth: 294)
                    bentoRow([4, 5, 6, 7], height: 400, minimumWidth: 294)
                }
                VStack(spacing: 16) {
                    bentoRow([0, 1, 2], height: 400, minimumWidth: 270)
                    bentoRow([3, 4, 5], height: 400, minimumWidth: 270)
                    bentoRow([6, 7], height: 400, minimumWidth: 410)
                }
                VStack(spacing: 16) {
                    bentoRow([0, 1], height: 350, minimumWidth: 270)
                    bentoRow([2, 3], height: 350, minimumWidth: 270)
                    bentoRow([4, 5], height: 350, minimumWidth: 270)
                    bentoRow([6, 7], height: 350, minimumWidth: 270)
                }
                VStack(spacing: 16) {
                    ForEach(layers.indices, id: \\.self) { index in
                        layerCard(index, height: 300)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 96)
        .frame(maxWidth: 1400)
    }

    private func bentoRow(_ indices: [Int], height: CGFloat, minimumWidth: CGFloat) -> some View {
        HStack(spacing: 16) {
            ForEach(indices, id: \\.self) { index in
                layerCard(index, height: height)
                    .frame(minWidth: minimumWidth, maxWidth: .infinity)
            }
        }
    }

    private func layerCard(_ index: Int, height: CGFloat) -> some View {
        let entry = layers[index]
        return Button {
            selectedExample = wallpaperResponse?.wallpapers.first(where: { $0.id == entry.exampleID })
        } label: {
            ZStack(alignment: .bottomLeading) {
                LayerPreview(kind: entry.kind)
                LinearGradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.kind == .basic ? "Basic Layer" : "\\(entry.kind.title) Layer")
                        .font(.system(size: 22, weight: .bold))
                    Text(entry.description)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(white: 0.82))
                        .lineLimit(horizontalSizeClass == .compact ? 2 : nil)
                }
                .padding(24)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(white: scheme == .dark ? 0.12 : 0.82), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(wallpaperResponse == nil)
        .accessibilityHint("Opens the example wallpaper used by the website")
    }

'''
s = s[:start] + section + s[end:]
p.write_text(s)
