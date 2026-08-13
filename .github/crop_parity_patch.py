from pathlib import Path
import re

path = Path('apps/ios/CAPlayground/Features/Editor/InspectorView.swift')
s = path.read_text()
pattern = re.compile(r'''private struct NativeImageCropSheet: View \{.*?\n\}\n\nprivate struct NativeImageBlurSheet''', re.S)
replacement = r'''private struct NativeImageCropSheet: View {
    private enum DragMode { case move, nw, ne, sw, se }

    @Environment(\.dismiss) private var dismiss
    let image: UIImage
    let onApply: (CGRect, Bool) -> Void
    @State private var x = 0.10
    @State private var y = 0.10
    @State private var width = 0.80
    @State private var height = 0.80
    @State private var maintainBounds = true
    @State private var dragMode: DragMode?
    @State private var dragStartCrop: CGRect?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Adjust the crop area and apply to replace the current image.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GeometryReader { geo in
                    let fit = aspectFitRect(image: image, in: geo.size)
                    let cropRect = CGRect(
                        x: fit.minX + CGFloat(x) * fit.width,
                        y: fit.minY + CGFloat(y) * fit.height,
                        width: CGFloat(width) * fit.width,
                        height: CGFloat(height) * fit.height
                    )
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)

                        Rectangle()
                            .fill(Color.black.opacity(0.20))
                            .overlay(Rectangle().stroke(Color.green, lineWidth: 2))
                            .frame(width: cropRect.width, height: cropRect.height)
                            .position(x: cropRect.midX, y: cropRect.midY)
                            .contentShape(Rectangle())
                            .gesture(cropGesture(.move, fit: fit))

                        cropHandle(.nw, at: CGPoint(x: cropRect.minX, y: cropRect.minY), fit: fit)
                        cropHandle(.ne, at: CGPoint(x: cropRect.maxX, y: cropRect.minY), fit: fit)
                        cropHandle(.sw, at: CGPoint(x: cropRect.minX, y: cropRect.maxY), fit: fit)
                        cropHandle(.se, at: CGPoint(x: cropRect.maxX, y: cropRect.maxY), fit: fit)
                    }
                }
                .frame(height: 340)
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                ViewThatFits(in: .horizontal) {
                    HStack {
                        Toggle("Maintain bounds after crop", isOn: $maintainBounds)
                        Spacer()
                        Text("Crop size: \(pixelSize.width) x \(pixelSize.height)px")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Maintain bounds after crop", isOn: $maintainBounds)
                        Text("Crop size: \(pixelSize.width) x \(pixelSize.height)px")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                    Button("Apply crop") {
                        onApply(.init(x: x, y: y, width: width, height: height), maintainBounds)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .navigationTitle("Crop image")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func cropHandle(_ mode: DragMode, at point: CGPoint, fit: CGRect) -> some View {
        Circle()
            .fill(Color.green)
            .overlay(Circle().stroke(Color.white, lineWidth: 1))
            .frame(width: 12, height: 12)
            .position(point)
            .contentShape(Circle().inset(by: -10))
            .gesture(cropGesture(mode, fit: fit))
    }

    private func cropGesture(_ mode: DragMode, fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard fit.width > 0, fit.height > 0 else { return }
                if dragMode != mode || dragStartCrop == nil {
                    dragMode = mode
                    dragStartCrop = CGRect(x: x, y: y, width: width, height: height)
                }
                guard let base = dragStartCrop else { return }
                let dx = Double(value.translation.width / fit.width)
                let dy = Double(value.translation.height / fit.height)
                applyDrag(mode, base: base, dx: dx, dy: dy)
            }
            .onEnded { _ in
                dragMode = nil
                dragStartCrop = nil
            }
    }

    private func applyDrag(_ mode: DragMode, base: CGRect, dx: Double, dy: Double) {
        let minSize = 0.05
        var nextX = Double(base.minX)
        var nextY = Double(base.minY)
        var nextW = Double(base.width)
        var nextH = Double(base.height)

        switch mode {
        case .move:
            nextX = clamp(Double(base.minX) + dx, 0, 1 - Double(base.width))
            nextY = clamp(Double(base.minY) + dy, 0, 1 - Double(base.height))
        case .se:
            nextW = clamp(Double(base.width) + dx, minSize, 1 - Double(base.minX))
            nextH = clamp(Double(base.height) + dy, minSize, 1 - Double(base.minY))
        case .sw:
            let newX = clamp(Double(base.minX) + dx, 0, Double(base.maxX) - minSize)
            nextW = clamp(Double(base.width) + (Double(base.minX) - newX), minSize, 1 - newX)
            nextX = newX
            nextH = clamp(Double(base.height) + dy, minSize, 1 - Double(base.minY))
        case .ne:
            let newY = clamp(Double(base.minY) + dy, 0, Double(base.maxY) - minSize)
            nextH = clamp(Double(base.height) + (Double(base.minY) - newY), minSize, 1 - newY)
            nextY = newY
            nextW = clamp(Double(base.width) + dx, minSize, 1 - Double(base.minX))
        case .nw:
            let newX = clamp(Double(base.minX) + dx, 0, Double(base.maxX) - minSize)
            let newY = clamp(Double(base.minY) + dy, 0, Double(base.maxY) - minSize)
            nextW = clamp(Double(base.width) + (Double(base.minX) - newX), minSize, 1 - newX)
            nextH = clamp(Double(base.height) + (Double(base.minY) - newY), minSize, 1 - newY)
            nextX = newX
            nextY = newY
        }

        nextX = clamp(nextX, 0, 1 - nextW)
        nextY = clamp(nextY, 0, 1 - nextH)
        x = nextX
        y = nextY
        width = nextW
        height = nextH
    }

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        max(lower, min(upper, value))
    }

    private var pixelSize: (width: Int, height: Int) {
        let w = image.cgImage?.width ?? Int(image.size.width * image.scale)
        let h = image.cgImage?.height ?? Int(image.size.height * image.scale)
        return (Int((Double(w) * width).rounded()), Int((Double(h) * height).rounded()))
    }

    private func aspectFitRect(image: UIImage, in size: CGSize) -> CGRect {
        let source = CGSize(width: max(image.size.width, 1), height: max(image.size.height, 1))
        let scale = min(size.width / source.width, size.height / source.height)
        let fitted = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }
}

private struct NativeImageBlurSheet'''
s2, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'crop replacement count={count}')
path.write_text(s2)
Path('.github/crop_parity_patch.py').unlink()
Path('.github/workflows/crop-parity.yml').unlink()
