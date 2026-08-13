from pathlib import Path

# Restore shared Inspector helpers removed by the final Filters patch.
inspector = Path('apps/ios/CAPlayground/Features/Editor/InspectorView.swift')
s = inspector.read_text()
anchor = '''    private func filterValueLabel(_ type: String) -> String { switch type { case "gaussianBlur": "Radius"; case "colorContrast", "colorSaturate": "Amount"; case "CISepiaTone": "Intensity"; case "colorHueRotate": "Angle"; default: "Value" } }

    private func applyBlur(to layer: LayerModel, amount: Double) {
'''
helpers = '''    private func filterValueLabel(_ type: String) -> String { switch type { case "gaussianBlur": "Radius"; case "colorContrast", "colorSaturate": "Amount"; case "CISepiaTone": "Intensity"; case "colorHueRotate": "Angle"; default: "Value" } }

    private func update(_ mutation: (inout LayerModel) -> Void) {
        guard let selectedID else { return }
        project.root.update(id: selectedID, mutation: mutation)
    }

    @MainActor private func importImage(_ url: URL) async {
        do {
            let imported = try await NativeImageAssetLoader.load(url)
            let name = project.uniqueAssetName(imported.filename, defaultExtension: "png")
            project.setAsset(imported.data, named: name)
            update { $0.imageName = name }
        } catch { }
    }

    @MainActor private func importEmitterCellImage(_ url: URL, targetID: UUID?) async {
        do {
            let imported = try await NativeImageAssetLoader.load(url)
            let name = project.uniqueAssetName(imported.filename, defaultExtension: "png")
            project.setAsset(imported.data, named: name)
            update { layer in
                if let targetID, let index = layer.emitterCells?.firstIndex(where: { $0.id == targetID }) {
                    layer.emitterCells?[index].imageName = name
                } else {
                    var cells = layer.emitterCells ?? []
                    var cell = EmitterCellModel()
                    cell.imageName = name
                    cells.append(cell)
                    layer.emitterCells = cells
                }
            }
        } catch { }
    }

    private func selectedImage(_ layer: LayerModel) -> UIImage? {
        guard let name = layer.imageName, let data = project.assetData(named: name) else { return nil }
        return UIImage(data: data)
    }

    private func resetImageBounds(_ layer: LayerModel) {
        guard let image = selectedImage(layer) else { return }
        let width = Double(image.cgImage?.width ?? Int(image.size.width * image.scale))
        let height = Double(image.cgImage?.height ?? Int(image.size.height * image.scale))
        updateSelectedSize(width: width, height: height)
    }

    private func updateSelectedSize(width: Double, height: Double) {
        guard let selectedID else { return }
        project.updateStateAware(
            targetID: selectedID,
            values: ["bounds.size.width": width, "bounds.size.height": height]
        ) { $0.size = .init(width: width, height: height) }
    }

    private func applyCrop(to layer: LayerModel, crop: CGRect, maintainBounds: Bool) {
        guard let image = selectedImage(layer), let source = image.cgImage else { return }
        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)
        let pixelRect = CGRect(
            x: crop.minX * sourceWidth,
            y: crop.minY * sourceHeight,
            width: crop.width * sourceWidth,
            height: crop.height * sourceHeight
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
        guard pixelRect.width > 0, pixelRect.height > 0, let cropped = source.cropping(to: pixelRect) else { return }
        let edited = UIImage(cgImage: cropped, scale: 1, orientation: .up)
        storeEditedImage(edited, originalName: layer.imageName ?? "image.png", suffix: "cropped")
        if !maintainBounds {
            updateSelectedSize(width: Double(cropped.width), height: Double(cropped.height))
        }
    }

    private func applyBlur(to layer: LayerModel, amount: Double) {
'''
if s.count(anchor) != 1:
    raise SystemExit(f'Inspector helper anchor count={s.count(anchor)}')
s = s.replace(anchor, helpers, 1)
inspector.write_text(s)

# Rewrite one Swift 6.3-invalid switch/if expression into ordinary assignment statements.
serializer = Path('apps/ios/CAPlayground/Export/CAMLSerializer.swift')
s = serializer.read_text()
old = '''                let encoded: (String, String) = switch value.value {
                case .number(let valueNumber):
                    if value.keyPath == "position.x" || value.keyPath == "position.y" {
                        ("integer", number(valueNumber.rounded()))
                    } else {
                        let converted = value.keyPath.hasPrefix("transform.rotation") ? valueNumber * .pi / 180 : valueNumber
                        (converted.rounded() == converted ? "integer" : "real", number(converted))
                    }
                case .string(let string):
                    (
                        value.keyPath == "backgroundColor" ? "CGColor" : "string",
                        value.keyPath == "backgroundColor" ? (color(string) ?? "1 1 1") : string
                    )
                }
'''
new = '''                let encoded: (String, String)
                switch value.value {
                case .number(let valueNumber):
                    if value.keyPath == "position.x" || value.keyPath == "position.y" {
                        encoded = ("integer", number(valueNumber.rounded()))
                    } else {
                        let converted = value.keyPath.hasPrefix("transform.rotation") ? valueNumber * .pi / 180 : valueNumber
                        encoded = (converted.rounded() == converted ? "integer" : "real", number(converted))
                    }
                case .string(let string):
                    encoded = (
                        value.keyPath == "backgroundColor" ? "CGColor" : "string",
                        value.keyPath == "backgroundColor" ? (color(string) ?? "1 1 1") : string
                    )
                }
'''
if s.count(old) != 1:
    raise SystemExit(f'Serializer encoded block count={s.count(old)}')
serializer.write_text(s.replace(old, new, 1))

# Remove the one-shot diagnostic workflow after this exact repair.
diag = Path('.github/workflows/ios-compile-diagnostics.yml')
if diag.exists():
    diag.unlink()
Path('.github/repair_inspector_serializer.py').unlink()
Path('.github/workflows/repair-inspector-serializer.yml').unlink()
