import XCTest
@testable import CAPlayground

final class ModelTests: XCTestCase {
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
}

private extension Data {
    func contains(_ other: Data) -> Bool { range(of: other) != nil }
}
