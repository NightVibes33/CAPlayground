import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TendiesCheckerView: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var importing = false
    @State private var fileName: String?
    @State private var result: TendiesAnalysis?
    @State private var error: String?
    @State private var isAnalysing = false
    @State private var previewAssets: [TendiesAssetInfo]?
    @State private var previewIndex = 0
    @State private var assetExportDocument: TendiesAssetExportDocument?
    @State private var assetExportType: UTType = .data
    @State private var assetExportFilename = "asset.bin"
    @State private var showingAssetExporter = false

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        VStack(spacing: 12) {
                            Text("Tendies Checker").font(.system(size: sizeClass == .compact ? 40 : 52, weight: .bold))
                            Text("Upload a .tendies file to see the info for the wallpaper.")
                                .font(sizeClass == .compact ? .subheadline : .body).foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .padding(.bottom, sizeClass == .compact ? 32 : 40)
                        checkerCard
                    }
                    .frame(maxWidth: 1024)
                    .padding(.horizontal, sizeClass == .compact ? 12 : 24)
                    .padding(.top, sizeClass == .compact ? 104 : 120)
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity)
                    CAWebsiteFooter()
                }
            }
            .background(CATheme.background(scheme).ignoresSafeArea())
            CAWebsiteNavigation().padding(.horizontal, sizeClass == .compact ? 16 : 24).padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.tendies], allowsMultipleSelection: false) { response in
            guard case .success(let urls) = response, let url = urls.first else { return }
            analyse(url)
        }
        .sheet(isPresented: Binding(get: { previewAssets != nil }, set: { if !$0 { previewAssets = nil; previewIndex = 0 } })) {
            assetPreview
        }
        .fileExporter(isPresented: $showingAssetExporter, document: assetExportDocument, contentType: assetExportType, defaultFilename: assetExportFilename) { response in
            if case .failure(let exportError) = response { error = exportError.localizedDescription }
            assetExportDocument = nil
        }
    }

    private var checkerCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Tendies File Analysis", systemImage: "doc.text").font(.title3.bold())
            Button { importing = true } label: {
                VStack(spacing: 10) {
                    if isAnalysing { ProgressView() } else { Image(systemName: "square.and.arrow.up").font(.title) }
                    Text(isAnalysing ? "Analysing tendies..." : "Drop a .tendies file here, or click to choose one").fontWeight(.medium)
                    Text("This tool will show CAPlayground info and per file breakdowns.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let fileName, !isAnalysing { Text("Selected file: \(fileName)").font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity).padding(sizeClass == .compact ? 24 : 32)
            }
            .buttonStyle(.plain)
            .background(CATheme.muted(scheme).opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(CATheme.border(scheme), style: StrokeStyle(lineWidth: 2, dash: [7])))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, url.pathExtension.lowercased() == "tendies" else { return false }
                analyse(url)
                return true
            }

            if let error {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Error", systemImage: "xmark.circle.fill").font(.headline)
                    Text(error).font(.subheadline)
                }
                .foregroundStyle(.red)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red.opacity(0.45)))
            }
            if let result { analysis(result) }
        }
        .padding(sizeClass == .compact ? 20 : 24)
        .background(CATheme.card(scheme), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(CATheme.border(scheme), lineWidth: 1) }
    }

    @ViewBuilder private func analysis(_ value: TendiesAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    Label("Project size: \(value.width) × \(value.height)", systemImage: "info.circle")
                    if value.video { Label("Video wallpaper detected (CAPlayground video layer with frame sequence)", systemImage: "info.circle").foregroundStyle(.orange) }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Label("Project size: \(value.width) × \(value.height)", systemImage: "info.circle")
                    if value.video { Label("Video wallpaper detected (CAPlayground video layer with frame sequence)", systemImage: "info.circle").foregroundStyle(.orange) }
                }
            }.font(.caption)

            VStack(alignment: .leading, spacing: 12) {
                Text("CAPlayground Info").font(.headline)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 32) {
                        status("Made in CAPlayground?", value.madeInCA, detail: "Requires both CA root layer and banner to be considered \"Yes\".")
                        status("Was the wallpaper remixed?", value.remixed ? "Yes" : "No", detail: "Detected via \"Imported from CAPlayground Gallery\".")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        status("Made in CAPlayground?", value.madeInCA, detail: "Requires both CA root layer and banner to be considered \"Yes\".")
                        status("Was the wallpaper remixed?", value.remixed ? "Yes" : "No", detail: "Detected via \"Imported from CAPlayground Gallery\".")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Per file breakdown").font(.headline)
                ForEach(value.documents) { document in documentBreakdown(document) }
            }

            HStack { Spacer(); Button("Clear") { clear() }.buttonStyle(CAWebButtonStyle(variant: .outline, height: 32)) }
        }
    }

    private func documentBreakdown(_ document: TendiesDocumentAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(document.title).font(.headline)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    countsColumn(document).frame(maxWidth: .infinity, alignment: .topLeading)
                    layerTypesColumn(document).frame(maxWidth: .infinity, alignment: .topLeading)
                    structureColumn(document).frame(maxWidth: .infinity, alignment: .topLeading)
                }
                VStack(alignment: .leading, spacing: 16) {
                    countsColumn(document); layerTypesColumn(document); structureColumn(document)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("IMAGES").font(.caption.bold()).foregroundStyle(.secondary)
                if document.assets.isEmpty {
                    Text("No images detected").font(.caption).foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 8) {
                            ForEach(Array(document.assets.enumerated()), id: \.element.id) { index, asset in
                                Button { previewAssets = document.assets; previewIndex = index } label: { assetThumbnail(asset) }
                                    .buttonStyle(.plain).accessibilityLabel("Preview \(asset.filename)")
                            }
                        }.padding(.vertical, 2)
                    }
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(CATheme.muted(scheme).opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CATheme.border(scheme).opacity(0.7)))
    }

    private func countsColumn(_ document: TendiesDocumentAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COUNTS").font(.caption.bold()).foregroundStyle(.secondary)
            Text("Layers: \(document.layers)"); Text("States: \(document.states)")
            Text("State transitions: \(document.transitions)"); Text("Animations: \(document.animations)")
        }.font(.caption)
    }

    private func layerTypesColumn(_ document: TendiesDocumentAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LAYER TYPES").font(.caption.bold()).foregroundStyle(.secondary)
            if document.layerTypes.isEmpty { Text("None").foregroundStyle(.secondary) }
            else {
                ForEach(document.layerTypes.keys.sorted(), id: \.self) { key in Text("\(key): \(document.layerTypes[key] ?? 0)") }
            }
        }.font(.caption)
    }

    private func structureColumn(_ document: TendiesDocumentAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("STRUCTURE").font(.caption.bold()).foregroundStyle(.secondary)
            if document.treeLines.isEmpty { Text("No layers parsed").foregroundStyle(.secondary) }
            else {
                ScrollView([.horizontal, .vertical]) {
                    Text(document.treeLines.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160).padding(8)
                .background(CATheme.background(scheme).opacity(0.65), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(CATheme.border(scheme).opacity(0.6)))
            }
        }.font(.caption)
    }

    private func assetThumbnail(_ asset: TendiesAssetInfo) -> some View {
        Group {
            if asset.isImage, let image = UIImage(data: asset.data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(asset.fileExtension.uppercased()).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64).background(CATheme.background(scheme))
        .clipShape(RoundedRectangle(cornerRadius: 6)).overlay(RoundedRectangle(cornerRadius: 6).stroke(CATheme.border(scheme)))
    }

    @ViewBuilder private var assetPreview: some View {
        NavigationStack {
            if let assets = previewAssets, !assets.isEmpty {
                let safeIndex = min(max(previewIndex, 0), assets.count - 1)
                let asset = assets[safeIndex]
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        if assets.count > 1 {
                            Button { previewIndex = (safeIndex - 1 + assets.count) % assets.count } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                                .buttonStyle(.bordered).accessibilityLabel("Previous asset")
                        }
                        Group {
                            if asset.isImage, let image = UIImage(data: asset.data) {
                                Image(uiImage: image).resizable().scaledToFit()
                            } else {
                                Text(asset.fileExtension.uppercased()).font(.headline.monospaced()).padding(20).overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if assets.count > 1 {
                            Button { previewIndex = (safeIndex + 1) % assets.count } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                                .buttonStyle(.bordered).accessibilityLabel("Next asset")
                        }
                    }
                    Text(asset.filename).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button("Download") { export(asset) }.buttonStyle(.borderedProminent)
                        Button("Close") { previewAssets = nil; previewIndex = 0 }.buttonStyle(.bordered)
                    }
                }
                .padding(20)
                .navigationTitle("Asset Preview").navigationBarTitleDisplayMode(.inline)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func status(_ title: String, _ answer: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(answer).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 4)
                    .foregroundStyle(answer == "Yes" ? .green : answer == "Maybe" ? .orange : .red)
                    .overlay(Capsule().stroke(CATheme.border(scheme)))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func analyse(_ url: URL) {
        fileName = url.lastPathComponent; result = nil; error = nil; isAnalysing = true
        Task {
            do {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let imported = try CAArchiveImporter.importProject(data: data, suggestedName: url.lastPathComponent)
                let entries = try ZIPArchive.extract(data).filter { $0.path.lowercased().hasSuffix("/main.caml") || $0.path.lowercased() == "main.caml" }
                let documents = entries.compactMap { entry -> TendiesDocumentAnalysis? in
                    guard let base = TendiesDocumentAnalysis(entry) else { return nil }
                    let kind: CADocumentKind = base.kind
                    let root = imported.documents[kind]?.root
                    let assets = imported.documentAssets[kind] ?? (imported.documentAssets.isEmpty ? imported.assets : [:])
                    return base.enriched(root: root, assets: assets)
                }
                guard !documents.isEmpty else { throw CAArchiveImportError.missingDocument }
                let video = imported.documents.values.map(\.root).contains { $0.flattened().contains { $0.kind == .video && ($0.frameCount ?? 0) >= 5 } }
                result = .init(width: Int(imported.width.rounded()), height: Int(imported.height.rounded()), documents: documents, video: video)
            } catch { self.error = error.localizedDescription }
            isAnalysing = false
        }
    }

    private func clear() {
        fileName = nil; result = nil; error = nil; previewAssets = nil; previewIndex = 0
    }

    private func export(_ asset: TendiesAssetInfo) {
        assetExportDocument = TendiesAssetExportDocument(data: asset.data)
        assetExportType = UTType(filenameExtension: asset.fileExtension) ?? .data
        assetExportFilename = asset.filename
        showingAssetExporter = true
    }
}

private struct TendiesAnalysis {
    let width: Int, height: Int
    let documents: [TendiesDocumentAnalysis]
    let video: Bool
    var madeInCA: String {
        let root = documents.contains(where: \.hasRoot), banner = documents.contains(where: \.hasBanner)
        return root && banner ? "Yes" : !root && !banner ? "No" : "Maybe"
    }
    var remixed: Bool { documents.contains(where: \.remixed) }
}

private struct TendiesDocumentAnalysis: Identifiable {
    let id = UUID()
    let title: String
    let kind: CADocumentKind
    let layers: Int
    let states: Int
    let transitions: Int
    let animations: Int
    let hasRoot: Bool
    let hasBanner: Bool
    let remixed: Bool
    var layerTypes: [String: Int] = [:]
    var treeLines: [String] = []
    var assets: [TendiesAssetInfo] = []

    init?(_ entry: ZIPEntry) {
        guard let xml = String(data: entry.data, encoding: .utf8) else { return nil }
        let path = entry.path.lowercased()
        if path.contains("floating") { kind = .floating; title = "Floating.ca" }
        else if path.contains("background") { kind = .background; title = "Background.ca" }
        else { kind = .wallpaper; title = "Wallpaper.ca" }
        layers = xml.matches("<CALayer\\b")
        states = xml.matches("<LKState\\b")
        transitions = xml.matches("<LKStateTransition\\b")
        animations = xml.matches("<animation\\b")
        let lower = xml.lowercased()
        hasRoot = lower.contains("id=\"__caprootlayer__\"") && lower.contains("name=\"caplayground root layer\"")
        hasBanner = lower.contains("caplayground") && lower.contains("create beautiful core animation wallpapers for ios")
        remixed = lower.contains("imported from caplayground gallery")
    }

    func enriched(root: LayerModel?, assets data: [String: Data]) -> Self {
        var copy = self
        if let root {
            for layer in root.flattened() { copy.layerTypes[layer.kind.rawValue, default: 0] += 1 }
            copy.treeLines = Self.treeLines(root)
        }
        copy.assets = data.keys.sorted().compactMap { name in data[name].map { TendiesAssetInfo(filename: name, data: $0) } }
        return copy
    }

    private static func treeLines(_ root: LayerModel, maxDepth: Int = 4, maxNodes: Int = 80) -> [String] {
        var output: [String] = [], count = 0
        func visit(_ layer: LayerModel, depth: Int) {
            guard count < maxNodes else { return }
            output.append(String(repeating: "  ", count: depth) + "- " + layer.name)
            count += 1
            guard depth < maxDepth else { return }
            for child in layer.children where count < maxNodes { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return output
    }
}

private struct TendiesAssetInfo: Identifiable {
    let filename: String
    let data: Data
    var id: String { filename }
    var fileExtension: String {
        let value = URL(fileURLWithPath: filename).pathExtension
        return value.isEmpty ? "file" : value
    }
    var isImage: Bool {
        let value = fileExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "gif", "svg", "bmp", "heic", "heif"].contains(value)
    }
}

private struct TendiesAssetExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private extension String {
    func matches(_ pattern: String) -> Int {
        (try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]).numberOfMatches(in: self, range: NSRange(startIndex..., in: self))) ?? 0
    }
}
