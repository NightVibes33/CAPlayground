import SwiftUI

struct EditorCanvasRepresentable: UIViewRepresentable {
    @Binding var project: CAProjectDocument
    @Binding var selectedID: UUID?
    var showBackground = true

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> EditorCanvasView {
        let view = EditorCanvasView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: EditorCanvasView, context: Context) {
        context.coordinator.parent = self
        view.display(project, selectedID: selectedID, showBackground: showBackground)
    }

    @MainActor
    final class Coordinator: EditorCanvasViewDelegate {
        var parent: EditorCanvasRepresentable
        init(parent: EditorCanvasRepresentable) { self.parent = parent }

        func canvas(_ canvas: EditorCanvasView, selected id: UUID?) { parent.selectedID = id }

        func canvas(_ canvas: EditorCanvasView, moved id: UUID, to position: Vector2) {
            parent.project.updateStateAware(targetID: id, values: ["position.x": position.x, "position.y": position.y]) { $0.position = position }
        }

        func canvas(_ canvas: EditorCanvasView, resized id: UUID, to size: LayerSize, position: Vector2) {
            parent.project.updateStateAware(targetID: id, values: ["bounds.size.width": size.width, "bounds.size.height": size.height, "position.x": position.x, "position.y": position.y]) { layer in
                layer.size = size
                layer.position = position
            }
        }

        func canvas(_ canvas: EditorCanvasView, rotated id: UUID, to degrees: Double) {
            parent.project.updateStateAware(targetID: id, values: ["transform.rotation.z": degrees]) { $0.rotation = degrees }
        }
    }
}

extension LayerModel {
    mutating func update(id: UUID, mutation: (inout LayerModel) -> Void) {
        if self.id == id {
            mutation(&self)
            return
        }
        for index in children.indices { children[index].update(id: id, mutation: mutation) }
    }

    func find(id: UUID) -> LayerModel? {
        if self.id == id { return self }
        for child in children { if let result = child.find(id: id) { return result } }
        return nil
    }

    mutating func remove(id: UUID) {
        children.removeAll { $0.id == id }
        for index in children.indices { children[index].remove(id: id) }
    }
}
