import SwiftUI
import UniformTypeIdentifiers

struct TendiesCheckerView: View {
    @Environment(\.colorScheme) private var scheme
    @State private var importing = false
    @State private var fileName: String?
    @State private var result: TendiesAnalysis?
    @State private var error: String?
    @State private var isAnalysing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Text("Tendies Checker").font(.system(size: 44, weight: .bold))
                    Text("Upload a .tendies file to see the info for the wallpaper.").foregroundStyle(.secondary)
                }.multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 20) {
                    Label("Tendies File Analysis", systemImage: "doc.text").font(.title3.bold())
                    Button { importing = true } label: {
                        VStack(spacing: 10) {
                            if isAnalysing { ProgressView() } else { Image(systemName: "square.and.arrow.up").font(.title) }
                            Text(isAnalysing ? "Analysing tendies..." : "Choose a .tendies file")
                            Text("This tool will show CAPlayground info and per file breakdowns.").font(.caption).foregroundStyle(.secondary)
                            if let fileName { Text("Selected file: \(fileName)").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity).padding(28)
                    }.buttonStyle(.plain)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 2, dash: [7])))
                    if let error { Label(error, systemImage: "xmark.circle.fill").foregroundStyle(.red) }
                    if let result { analysis(result) }
                }.padding(20).caPanel()
            }.frame(maxWidth: 960).padding(.horizontal, 16).padding(.vertical, 40)
        }.background(CATheme.background(scheme).ignoresSafeArea())
            .navigationTitle("Tendies Checker").navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.tendies, .zip], allowsMultipleSelection: false) { response in
                guard case .success(let urls) = response, let url = urls.first else { return }; analyse(url)
            }
    }

    @ViewBuilder private func analysis(_ value: TendiesAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Label("Project size: \(value.width) × \(value.height)", systemImage: "info.circle"); if value.video { Text("Video wallpaper detected").foregroundStyle(.orange) } }.font(.caption)
            Text("CAPlayground Info").font(.headline)
            ViewThatFits {
                HStack(alignment: .top, spacing: 32) { status("Made in CAPlayground?", value.madeInCA); status("Was the wallpaper remixed?", value.remixed ? "Yes" : "No") }
                VStack(alignment: .leading, spacing: 16) { status("Made in CAPlayground?", value.madeInCA); status("Was the wallpaper remixed?", value.remixed ? "Yes" : "No") }
            }
            Text("Per file breakdown").font(.headline)
            ForEach(value.documents) { document in
                VStack(alignment: .leading, spacing: 10) {
                    Text(document.title).font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 5) {
                        GridRow { Text("Layers"); Text("\(document.layers)") }; GridRow { Text("States"); Text("\(document.states)") }
                        GridRow { Text("State transitions"); Text("\(document.transitions)") }; GridRow { Text("Animations"); Text("\(document.animations)") }
                    }.font(.caption)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            Button("Clear") { fileName = nil; result = nil; error = nil }.buttonStyle(.bordered)
        }
    }

    private func status(_ title: String, _ answer: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
            Text(answer).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 4)
                .foregroundStyle(answer == "Yes" ? .green : answer == "Maybe" ? .orange : .red).overlay(Capsule().stroke(.secondary.opacity(0.35)))
        }
    }

    private func analyse(_ url: URL) {
        fileName = url.lastPathComponent; result = nil; error = nil; isAnalysing = true
        Task {
            do {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url), imported = try CAArchiveImporter.importProject(data: data, suggestedName: url.lastPathComponent)
                let documents = try ZIPArchive.extract(data).filter { $0.path.lowercased().hasSuffix("/main.caml") || $0.path.lowercased() == "main.caml" }.compactMap(TendiesDocumentAnalysis.init)
                guard !documents.isEmpty else { throw CAArchiveImportError.missingDocument }
                let video = imported.documents.values.map(\.root).contains { $0.flattened().contains { $0.kind == .video && ($0.frameCount ?? 0) >= 5 } }
                result = .init(width: Int(imported.width.rounded()), height: Int(imported.height.rounded()), documents: documents, video: video)
            } catch { self.error = error.localizedDescription }
            isAnalysing = false
        }
    }
}

private struct TendiesAnalysis {
    let width: Int, height: Int; let documents: [TendiesDocumentAnalysis]; let video: Bool
    var madeInCA: String { let root = documents.contains(where: \.hasRoot), banner = documents.contains(where: \.hasBanner); return root && banner ? "Yes" : !root && !banner ? "No" : "Maybe" }
    var remixed: Bool { documents.contains(where: \.remixed) }
}

private struct TendiesDocumentAnalysis: Identifiable {
    let id = UUID(), title: String, layers: Int, states: Int, transitions: Int, animations: Int
    let hasRoot: Bool, hasBanner: Bool, remixed: Bool
    init?(_ entry: ZIPEntry) {
        guard let xml = String(data: entry.data, encoding: .utf8) else { return nil }; let path = entry.path.lowercased()
        title = path.contains("floating") ? "Floating.ca" : path.contains("background") ? "Background.ca" : "Wallpaper.ca"
        layers = xml.matches("<CALayer\\b"); states = xml.matches("<LKState\\b"); transitions = xml.matches("<LKStateTransition\\b"); animations = xml.matches("<animation\\b")
        let lower = xml.lowercased(); hasRoot = lower.contains("id=\"__caprootlayer__\"") && lower.contains("name=\"caplayground root layer\"")
        hasBanner = lower.contains("caplayground") && lower.contains("create beautiful core animation wallpapers for ios"); remixed = lower.contains("imported from caplayground gallery")
    }
}

private extension String { func matches(_ pattern: String) -> Int { (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]).numberOfMatches(in: self, range: NSRange(startIndex..., in: self))) ?? 0 } }
private extension LayerModel { func flattened() -> [LayerModel] { [self] + children.flatMap { $0.flattened() } } }
