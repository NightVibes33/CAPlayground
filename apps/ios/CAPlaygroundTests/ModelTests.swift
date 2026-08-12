import XCTest
@testable import CAPlayground

final class ModelTests: XCTestCase {
    func testProjectWithoutAssetsStillDecodes() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let project = CAProjectDocument.blank()
        let encoded = try encoder.encode(project)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "assets")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CAProjectDocument.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.assets.isEmpty)
    }

    func testProjectRoundTripPreservesNativeLayerTree() throws {
        var project = CAProjectDocument.blank(name: "Fixture")
        project.root.children.append(
            LayerModel(id: UUID(), name: "Gradient", kind: .gradient,
                       position: .init(x: 195, y: 422), size: .init(width: 390, height: 844),
                       gradientType: "axial", gradientStart: .init(x: 0, y: 0),
                       gradientEnd: .init(x: 1, y: 1),
                       gradientStops: [.init(color: "#6366F1", opacity: 1),
                                       .init(color: "#5AD197", opacity: 1)])
        )
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(CAProjectDocument.self, from: data)
        XCTAssertEqual(decoded, project)
        XCTAssertEqual(decoded.root.children.first?.kind, .gradient)
    }

    func testRecursiveLayerMutation() {
        let childID = UUID()
        var root = CAProjectDocument.blank().root
        root.children = [LayerModel(id: childID, name: "Text", kind: .text,
                                    position: .init(x: 0, y: 0), size: .init(width: 100, height: 40))]
        root.update(id: childID) { $0.opacity = 0.25 }
        XCTAssertEqual(root.find(id: childID)?.opacity, 0.25)
    }

    func testCAMLContainsDualCADocumentSemantics() {
        let project = CAProjectDocument.blank(name: "Fixture")
        let document = project.documents[.floating]!
        let output = CAMLSerializer.serialize(project: project, document: document, kind: .floating)
        XCTAssertTrue(output.contains("CAPlayground Root Layer"))
        XCTAssertTrue(output.contains("<states>"))
        XCTAssertTrue(output.contains("Locked"))
        XCTAssertTrue(output.contains("<stateTransitions>"))
    }

    func testZIPHasValidSignatures() throws {
        let archive = ZIPArchive.create(entries: [.init(path: "Floating.ca/main.caml", data: Data("test".utf8))])
        XCTAssertEqual(Array(archive.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
        XCTAssertTrue(archive.contains(Data([0x50, 0x4b, 0x05, 0x06])))
    }

    func testNativeCAExportCanBeImported() throws {
        var project = CAProjectDocument.blank(name: "Fixture")
        project.root.children.append(
            LayerModel(id: UUID(), name: "Imported Text", kind: .text,
                       position: .init(x: 100, y: 200), size: .init(width: 180, height: 60),
                       text: "Hello", fontSize: 28, textColor: "#FFFFFF")
        )
        let archive = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
        let imported = try CAArchiveImporter.importProject(data: archive, suggestedName: "Fixture.ca")
        XCTAssertEqual(imported.name, "Fixture.ca")
        XCTAssertEqual(imported.documents[.floating]?.root.children.first?.name, "Imported Text")
        XCTAssertEqual(imported.documents[.floating]?.root.children.first?.text, "Hello")
    }

    func testLayerDuplicateRefreshesEveryID() {
        let child = LayerModel(id: UUID(), name: "Child", kind: .basic,
                               position: .init(x: 10, y: 10), size: .init(width: 20, height: 20))
        let original = LayerModel(id: UUID(), name: "Parent", kind: .transform, children: [child],
                                  position: .init(x: 50, y: 50), size: .init(width: 100, height: 100))
        var root = CAProjectDocument.blank().root
        root.children = [original]
        let duplicateID = root.duplicate(id: original.id)
        XCTAssertNotNil(duplicateID)
        XCTAssertEqual(root.children.count, 2)
        XCTAssertNotEqual(root.children[0].id, root.children[1].id)
        XCTAssertNotEqual(root.children[0].children[0].id, root.children[1].children[0].id)
    }

    func testStateAwareMutationPreservesBaseLayer() {
        let layerID = UUID()
        var project = CAProjectDocument.blank()
        project.root.children = [LayerModel(id: layerID, name: "Layer", kind: .basic,
                                            position: .init(x: 10, y: 20), size: .init(width: 30, height: 40))]
        project.activeState = "Locked"
        project.updateStateAware(targetID: layerID, values: ["position.x": 99]) { $0.position.x = 99 }
        XCTAssertEqual(project.root.find(id: layerID)?.position.x, 10)
        XCTAssertEqual(project.overrideValue(targetID: layerID, keyPath: "position.x"), .number(99))
    }

    func testZIPExtractionPreservesAssets() throws {
        let expected = Data([0, 1, 2, 3, 255])
        let archive = ZIPArchive.create(entries: [.init(path: "Floating.ca/assets/image.png", data: expected)])
        let extracted = try ZIPArchive.extract(archive)
        XCTAssertEqual(extracted.first?.path, "Floating.ca/assets/image.png")
        XCTAssertEqual(extracted.first?.data, expected)
    }
}

private extension Data {
    func contains(_ other: Data) -> Bool { range(of: other) != nil }
}
