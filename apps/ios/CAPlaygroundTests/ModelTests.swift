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

    func testWebsiteCompatibleAnimationTagsAreSerialized() {
        var project = CAProjectDocument.blank(name: "Animation")
        let animatedID = UUID()
        var layer = LayerModel(id: animatedID, name: "Animated", kind: .basic,
                               position: .init(x: 100, y: 100), size: .init(width: 80, height: 80))
        layer.animations = [
            KeyframeAnimationModel(keyPath: "opacity", numericValues: [0, 1], keyTimes: [0, 1], duration: 2),
            KeyframeAnimationModel(keyPath: "transform.rotation.z", numericValues: [0, 180], keyTimes: [0, 1], duration: 3)
        ]
        project.root.children = [layer]
        let output = CAMLSerializer.serialize(project: project, document: project.documents[.floating]!, kind: .floating)
        XCTAssertTrue(output.contains("<animation type=\"CAKeyframeAnimation\""))
        XCTAssertTrue(output.contains("<p type=\"CAKeyframeAnimation\""))
        XCTAssertFalse(output.contains("<CAKeyframeAnimation keyPath="))
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
                       text: "Hello", fontFamily: "SFProText-Regular", fontSize: 28, textColor: "#FFFFFF")
        )
        let archive = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
        let imported = try CAArchiveImporter.importProject(data: archive, suggestedName: "Fixture.ca")
        XCTAssertEqual(imported.name, "Fixture.ca")
        XCTAssertEqual(imported.documents[.floating]?.root.children.first?.name, "Imported Text")
        XCTAssertEqual(imported.documents[.floating]?.root.children.first?.text, "Hello")
        XCTAssertEqual(imported.documents[.floating]?.root.children.first?.fontFamily, "SFProText-Regular")
    }

    func testCAArchiveRoundTripPreservesAdvancedWebsiteControls() throws {
        var project = CAProjectDocument.blank(name: "Advanced")
        let gradientID = UUID()
        let emitterID = UUID()

        var gradient = LayerModel(
            id: gradientID, name: "Gradient", kind: .gradient,
            position: .init(x: 140, y: 220), size: .init(width: 200, height: 300),
            opacity: 0.82, rotation: 17, backgroundOpacity: 0.7,
            blendMode: "multiply",
            filters: [
                FilterModel(type: "gaussianBlur", value: 12),
                FilterModel(type: "colorHueRotate", value: 45),
                FilterModel(type: "CISepiaTone", value: 0.4)
            ],
            gradientType: "radial",
            gradientStart: .init(x: 0.1, y: 0.2),
            gradientEnd: .init(x: 0.9, y: 0.8),
            gradientStops: [
                .init(color: "#112233", opacity: 0.5),
                .init(color: "#AABBCC", opacity: 1)
            ]
        )
        gradient.animations = [
            KeyframeAnimationModel(
                keyPath: "position",
                numericValues: [],
                values: [.point(.init(x: 20, y: 30)), .point(.init(x: 160, y: 240))],
                keyTimes: [0, 1], duration: 1.75, autoreverses: true, repeats: false,
                calculationMode: "linear", timingFunction: "easeInEaseOut", repeatDurationSeconds: 1.75, speed: 0.8
            )
        ]

        var cell = EmitterCellModel()
        cell.name = "Spark"
        cell.imageName = "spark.png"
        cell.birthRate = 31
        cell.lifetime = 4.5
        cell.lifetimeRange = 1.2
        cell.velocity = 88
        cell.velocityRange = 9
        cell.emissionLongitude = 1.1
        cell.emissionLatitude = 0.2
        cell.emissionRange = 2.6
        cell.scale = 0.12
        cell.scaleRange = 0.04
        cell.scaleSpeed = -0.01
        cell.alphaRange = 0.3
        cell.alphaSpeed = -0.2
        cell.spin = 0.9
        cell.spinRange = 0.4
        cell.xAcceleration = 2
        cell.yAcceleration = 13
        cell.color = "#FF8844"

        var emitter = LayerModel(
            id: emitterID, name: "Particles", kind: .emitter,
            position: .init(x: 195, y: 422), size: .init(width: 390, height: 844),
            emitterPosition: .init(x: 195, y: 20), emitterSize: .init(width: 390, height: 20),
            emitterShape: "line", emitterMode: "surface", renderMode: "additive",
            emitterCells: [cell]
        )
        emitter.gyroDictionaries = [
            GyroDictionaryModel(axis: "x", keyPath: "position.x", layerName: "Particles", mapMinTo: -30, mapMaxTo: 30, title: "Tilt", view: "Wallpaper")
        ]

        project.root.children = [gradient, emitter]
        project.assets["spark.png"] = Data([1, 2, 3, 4, 5])
        project.states = ["Locked", "Unlock", "Sleep"]
        project.stateOverrides = [
            "Locked": [StateOverride(targetID: gradientID, keyPath: "opacity", value: .number(0.25))]
        ]
        project.stateTransitions = [
            StateTransition(fromState: "Locked", toState: "Unlock", elements: [
                StateTransitionElement(targetID: gradientID, keyPath: "position", animation: SpringAnimationModel(damping: 14, mass: 1.2, stiffness: 130, initialVelocity: 0.5, duration: 0.8, fillMode: "both", keyPath: "position", micaAutorecalculatesDuration: true))
            ])
        ]

        let archive = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
        let imported = try CAArchiveImporter.importProject(data: archive, suggestedName: "Advanced.ca")
        let importedRoot = try XCTUnwrap(imported.documents[.floating]?.root)
        let importedGradient = try XCTUnwrap(importedRoot.find(id: gradientID))
        let importedEmitter = try XCTUnwrap(importedRoot.find(id: emitterID))

        XCTAssertEqual(imported.assets["spark.png"], project.assets["spark.png"])
        XCTAssertEqual(importedGradient.kind, .gradient)
        XCTAssertEqual(importedGradient.gradientType, "radial")
        XCTAssertEqual(importedGradient.gradientStart?.x, 0.1, accuracy: 0.0001)
        XCTAssertEqual(importedGradient.gradientEnd?.y, 0.8, accuracy: 0.0001)
        XCTAssertEqual(importedGradient.gradientStops?.count, 2)
        XCTAssertEqual(importedGradient.blendMode, "multiply")
        XCTAssertEqual(importedGradient.filters.count, 3)
        XCTAssertEqual(importedGradient.animations.count, 1)
        XCTAssertEqual(importedGradient.animations.first?.keyPath, "position")
        XCTAssertEqual(importedGradient.animations.first?.values?.count, 2)
        XCTAssertEqual(importedEmitter.emitterShape, "line")
        XCTAssertEqual(importedEmitter.emitterMode, "surface")
        XCTAssertEqual(importedEmitter.emitterCells?.first?.name, "Spark")
        XCTAssertEqual(importedEmitter.emitterCells?.first?.imageName, "spark.png")
        XCTAssertEqual(importedEmitter.emitterCells?.first?.birthRate, 31)
        XCTAssertEqual(importedEmitter.gyroDictionaries?.first?.layerName, "Particles")
        XCTAssertEqual(imported.documents[.floating]?.stateOverrides["Locked"]?.first?.value, .number(0.25))
        XCTAssertEqual(imported.documents[.floating]?.stateTransitions.first?.fromState, "Locked")
        XCTAssertEqual(imported.documents[.floating]?.stateTransitions.first?.elements.first?.animation?.damping, 14)
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
