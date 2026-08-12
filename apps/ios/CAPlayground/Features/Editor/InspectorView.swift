import SwiftUI

struct InspectorView: View {
    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?

    var body: some View {
        Group {
            if let id = selectedID, let layer = project.root.find(id: id) {
                Form {
                    Section("Layer") {
                        TextField("Name", text: binding(id, \.name, fallback: layer.name))
                        LabeledContent("Type", value: layer.kind.title)
                        Toggle("Visible", isOn: binding(id, \.isVisible, fallback: true))
                    }
                    Section("Geometry") {
                        numeric("X", id: id, keyPath: \.position.x, value: layer.position.x)
                        numeric("Y", id: id, keyPath: \.position.y, value: layer.position.y)
                        numeric("Width", id: id, keyPath: \.size.width, value: layer.size.width)
                        numeric("Height", id: id, keyPath: \.size.height, value: layer.size.height)
                        numeric("Rotation", id: id, keyPath: \.rotation, value: layer.rotation)
                        numeric("Scale", id: id, keyPath: \.scale, value: layer.scale)
                    }
                    Section("Appearance") {
                        VStack(alignment: .leading) {
                            LabeledContent("Opacity", value: layer.opacity.formatted(.number.precision(.fractionLength(2))))
                            Slider(value: binding(id, \.opacity, fallback: 1), in: 0...1)
                        }
                        numeric("Corner radius", id: id, keyPath: \.cornerRadius, value: layer.cornerRadius)
                        numeric("Border width", id: id, keyPath: \.borderWidth, value: layer.borderWidth)
                    }
                    if layer.kind == .text {
                        Section("Text") {
                            TextField("Text", text: optionalStringBinding(id, \.text, fallback: layer.text ?? ""))
                            numeric("Font size", id: id, keyPath: \.fontSize, value: layer.fontSize ?? 32)
                        }
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("No Layer Selected", systemImage: "cursorarrow.click.2",
                                       description: Text("Choose a layer from the canvas or layer list."))
            }
        }
        .caPanel()
    }

    private func binding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<LayerModel, Value>, fallback: Value) -> Binding<Value> {
        Binding {
            project.root.find(id: id)?[keyPath: keyPath] ?? fallback
        } set: { newValue in
            project.root.update(id: id) { $0[keyPath: keyPath] = newValue }
        }
    }

    private func optionalStringBinding(_ id: UUID, _ keyPath: WritableKeyPath<LayerModel, String?>, fallback: String) -> Binding<String> {
        Binding {
            project.root.find(id: id)?[keyPath: keyPath] ?? fallback
        } set: { newValue in
            project.root.update(id: id) { $0[keyPath: keyPath] = newValue }
        }
    }

    @ViewBuilder
    private func numeric(_ title: String, id: UUID, keyPath: WritableKeyPath<LayerModel, Double>, value: Double) -> some View {
        LabeledContent(title) {
            TextField(title, value: binding(id, keyPath, fallback: value), format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
        }
    }
}
