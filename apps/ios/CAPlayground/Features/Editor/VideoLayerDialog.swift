import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct VideoLayerDialog: View {
    private static let maxDuration = 12.0

    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var pickerOpen = false
    @State private var sourceURL: URL?
    @State private var sourceName = ""
    @State private var fps = 30
    @State private var resizeVideo = true
    @State private var quality = 0.85
    @State private var isLoading = false
    @State private var currentFrame = 0
    @State private var frameCount = 0
    @State private var frames: [Data] = []
    @State private var width = 0
    @State private var height = 0
    @State private var duration = 0.0
    @State private var error: String?
    @State private var generationID = UUID()

    private var isGIF: Bool { sourceURL?.pathExtension.lowercased() == "gif" }
    private var frameAssetsSize: Int { frames.reduce(0) { $0 + $1.count } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Upload a video or GIF to create a video layer. The video will be converted to individual frames.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button { pickerOpen = true } label: {
                            Label(sourceName.isEmpty ? "Choose video or GIF" : sourceName, systemImage: "square.and.arrow.up")
                                .lineLimit(1).frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered)
                        Picker("Select frames per second", selection: $fps) {
                            Text("15 fps").tag(15); Text("30 fps").tag(30); Text("60 fps").tag(60)
                        }
                        .labelsHidden().pickerStyle(.menu).frame(width: 104).disabled(isGIF)
                    }

                    if sourceURL != nil && !isGIF {
                        Toggle("Resize to fit canvas", isOn: $resizeVideo)
                    }

                    VStack(spacing: 8) {
                        HStack { Text("Frame Quality").font(.subheadline.weight(.medium)); Spacer(); Text("\(Int((quality * 100).rounded()))%").foregroundStyle(.secondary) }
                        Slider(value: $quality, in: 0.10...1, step: 0.05)
                        Text("Lower quality = smaller file size.").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text("Dimensions: \(width)x\(height)px").font(.subheadline.weight(.medium))
                    Text("Duration: \(duration.formatted(.number.precision(.fractionLength(2))))s").font(.subheadline.weight(.medium))
                    Text(isLoading ? "Layer Size: Generating frames... (\(currentFrame)/\(frameCount))" : "Layer Size: \(formatBytes(frameAssetsSize))")
                        .font(.subheadline.weight(.medium))

                    if !isLoading && frameAssetsSize > 30 * 1024 * 1024 {
                        Label("Warning: Layer size exceeds 30MB. This may impact performance and memory usage.", systemImage: "exclamationmark.triangle")
                            .font(.subheadline).foregroundStyle(.red).padding(12)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.red))
                    }

                    ProgressView(value: frameCount > 0 ? Double(currentFrame) / Double(frameCount) : 0)

                    Text(isGIF
                         ? "For GIFs, the frame rate is automatically set to 15 fps for optimal performance."
                         : "Note: 30 fps is recommended for optimal performance. Higher frame rates (60 fps) are better for videos synced with state transitions but will increase file size.")
                        .font(.subheadline).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                    if let error { Text(error).font(.subheadline).foregroundStyle(.red) }
                }.padding(20)
            }
            .navigationTitle("Video Layer").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Video Layer") { createLayer() }.disabled(sourceURL == nil || isLoading || frames.isEmpty)
                }
            }
            .fileImporter(isPresented: $pickerOpen, allowedContentTypes: [.movie, .gif], allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                sourceURL = url; sourceName = url.lastPathComponent
                if url.pathExtension.lowercased() == "gif" { fps = 15; quality = 1 }
                else { fps = 30; quality = 0.85 }
                regenerate()
            }
            .onChange(of: fps) { _, _ in regenerate() }
            .onChange(of: resizeVideo) { _, _ in regenerate() }
            .onChange(of: quality) { _, _ in regenerate() }
            .task { try? await Task.sleep(for: .milliseconds(100)); pickerOpen = true }
        }
        .interactiveDismissDisabled(isLoading)
    }

    private func regenerate() {
        guard let sourceURL else { return }
        let requestedFPS = fps
        let requestedQuality = quality
        let requestedResize = resizeVideo
        let requestID = UUID()
        generationID = requestID
        frames = []; frameCount = 0; currentFrame = 0; error = nil; isLoading = true
        Task {
            do {
                let result = try await VideoFrameExtractor.extract(
                    url: sourceURL, fps: requestedFPS, quality: requestedQuality,
                    resizeTo: requestedResize ? CGSize(width: project.width, height: project.height) : nil,
                    maxDuration: Self.maxDuration
                )
                guard generationID == requestID, self.sourceURL == sourceURL, fps == requestedFPS, quality == requestedQuality, resizeVideo == requestedResize else { return }
                frames = result.frames; frameCount = result.frames.count; currentFrame = result.frames.count
                width = result.width; height = result.height; duration = result.duration
            } catch where generationID == requestID { self.error = error.localizedDescription }
            catch { }
            if generationID == requestID { isLoading = false }
        }
    }

    private func createLayer() {
        guard !frames.isEmpty else { return }
        let rawBase = URL(fileURLWithPath: sourceName).deletingPathExtension().lastPathComponent
        let safeBase = rawBase.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
        let prefix = "\(safeBase.isEmpty ? "Video_Layer" : safeBase)_"
        for (index, data) in frames.enumerated() { project.assets["\(prefix)\(index).jpg"] = data }
        let id = UUID()
        var layer = LayerModel(
            id: id, name: nextName(sourceName.isEmpty ? "Video Layer" : sourceName), kind: .video,
            position: insertionPosition(), size: .init(width: Double(width), height: Double(height))
        )
        layer.framePrefix = prefix; layer.frameExtension = ".jpg"; layer.frameCount = frames.count
        layer.framesPerSecond = Double(fps); layer.videoDuration = duration; layer.calculationMode = "discrete"
        if let selectedID, project.root.find(id: selectedID)?.kind != .emitter { project.root.update(id: selectedID) { $0.children.append(layer) } }
        else { project.root.children.append(layer) }
        selectedID = id
        dismiss()
    }

    private func insertionPosition() -> Vector2 {
        let parent = selectedID.flatMap { project.root.find(id: $0) }
        return .init(x: (parent?.size.width ?? project.width) / 2, y: (parent?.size.height ?? project.height) / 2)
    }

    private func nextName(_ base: String) -> String {
        let names = Set(project.root.flattened().map(\.name)); guard names.contains(base) else { return base }
        var index = 2; while names.contains("\(base) \(index)") { index += 1 }; return "\(base) \(index)"
    }

    private func formatBytes(_ bytes: Int) -> String {
        guard bytes > 0 else { return "0 Bytes" }
        let units = ["Bytes", "KB", "MB", "GB"]
        let index = min(Int(log(Double(bytes)) / log(1024)), units.count - 1)
        let value = Double(bytes) / pow(1024, Double(index))
        return "~\((value * 100).rounded() / 100) \(units[index])"
    }
}

private enum VideoFrameExtractor {
    struct Result: Sendable { var frames: [Data]; var width: Int; var height: Int; var duration: Double }

    static func extract(url: URL, fps: Int, quality: Double, resizeTo: CGSize?, maxDuration: Double) async throws -> Result {
        try await Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if url.pathExtension.lowercased() == "gif" { return try extractGIF(url: url, quality: quality) }
            let asset = AVURLAsset(url: url)
            let loadedDuration = try await asset.load(.duration).seconds
            guard loadedDuration.isFinite, loadedDuration > 0 else { throw CocoaError(.fileReadCorruptFile) }
            let duration = min(loadedDuration, maxDuration)
            let count = max(1, Int(floor(duration * Double(fps))))
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            if let resizeTo { generator.maximumSize = resizeTo }
            var frames: [Data] = []; var width = 0; var height = 0
            for index in 0..<count {
                try Task.checkCancellation()
                let image = try generator.copyCGImage(at: CMTime(seconds: Double(index) / Double(fps), preferredTimescale: 600), actualTime: nil)
                width = image.width; height = image.height
                if let data = UIImage(cgImage: image).jpegData(compressionQuality: quality) { frames.append(data) }
            }
            return Result(frames: frames, width: width, height: height, duration: duration)
        }.value
    }

    private static func extractGIF(url: URL, quality: Double) throws -> Result {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else { throw CocoaError(.fileReadCorruptFile) }
        var frames: [Data] = []; var width = 0; var height = 0; var duration = 0.0
        for index in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            width = image.width; height = image.height
            if let data = UIImage(cgImage: image).jpegData(compressionQuality: quality) { frames.append(data) }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            duration += gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? (1.0 / 15.0)
        }
        return Result(frames: frames, width: width, height: height, duration: duration)
    }
}
