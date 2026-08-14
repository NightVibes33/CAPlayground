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
        object.removeValue(forKey: "documentAssets")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CAProjectDocument.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.assets.isEmpty)
        XCTAssertTrue(decoded.documentAssets.isEmpty)
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
        XCTAssertEqual(imported.name, "Fixture")
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
        cell.contentsScale = 2.25
        cell.birthRate = 31
        cell.lifetime = 4.5
        cell.lifetimeRange = 1.2
        cell.velocity = 88
        cell.velocityRange = 9
        cell.emissionLongitude = 63
        cell.emissionLatitude = 11
        cell.emissionRange = 149
        cell.scale = 0.12
        cell.scaleRange = 0.04
        cell.scaleSpeed = -0.01
        cell.alpha = 0.73
        cell.alphaRange = 0.3
        cell.alphaSpeed = -0.2
        cell.spin = 52
        cell.spinRange = 23
        cell.xAcceleration = 2
        cell.yAcceleration = 13
        cell.color = "#FF8844"
        cell.redRange = 0.11
        cell.redSpeed = -0.07
        cell.greenRange = 0.22
        cell.greenSpeed = 0.08
        cell.blueRange = 0.33
        cell.blueSpeed = -0.09

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
        let importedCell = try XCTUnwrap(importedEmitter.emitterCells?.first)
        let gradientStartX = try XCTUnwrap(importedGradient.gradientStart?.x)
        let gradientEndY = try XCTUnwrap(importedGradient.gradientEnd?.y)

        XCTAssertEqual(imported.assets["spark.png"], project.assets["spark.png"])
        XCTAssertEqual(importedGradient.kind, .gradient)
        XCTAssertEqual(importedGradient.gradientType, "radial")
        XCTAssertEqual(gradientStartX, 0.1, accuracy: 0.0001)
        XCTAssertEqual(gradientEndY, 0.8, accuracy: 0.0001)
        XCTAssertEqual(importedGradient.gradientStops?.count, 2)
        XCTAssertEqual(importedGradient.blendMode, "multiply")
        XCTAssertEqual(importedGradient.filters.count, 3)
        XCTAssertEqual(importedGradient.animations.count, 1)
        XCTAssertEqual(importedGradient.animations.first?.keyPath, "position")
        XCTAssertEqual(importedGradient.animations.first?.values?.count, 2)
        XCTAssertEqual(importedEmitter.emitterShape, "line")
        XCTAssertEqual(importedEmitter.emitterMode, "surface")
        XCTAssertEqual(importedCell.name, "Spark")
        XCTAssertEqual(importedCell.imageName, "spark.png")
        XCTAssertEqual(importedCell.contentsScale, 2.25, accuracy: 0.0001)
        XCTAssertEqual(importedCell.birthRate, 31, accuracy: 0.0001)
        XCTAssertEqual(importedCell.emissionLongitude, 63, accuracy: 0.001)
        XCTAssertEqual(importedCell.emissionLatitude, 11, accuracy: 0.001)
        XCTAssertEqual(importedCell.emissionRange, 149, accuracy: 0.001)
        XCTAssertEqual(importedCell.alpha, 0.73, accuracy: 0.0001)
        XCTAssertEqual(importedCell.spin, 52, accuracy: 0.001)
        XCTAssertEqual(importedCell.spinRange, 23, accuracy: 0.001)
        XCTAssertEqual(importedCell.redRange, 0.11, accuracy: 0.0001)
        XCTAssertEqual(importedCell.redSpeed, -0.07, accuracy: 0.0001)
        XCTAssertEqual(importedCell.greenRange, 0.22, accuracy: 0.0001)
        XCTAssertEqual(importedCell.greenSpeed, 0.08, accuracy: 0.0001)
        XCTAssertEqual(importedCell.blueRange, 0.33, accuracy: 0.0001)
        XCTAssertEqual(importedCell.blueSpeed, -0.09, accuracy: 0.0001)
        XCTAssertEqual(importedEmitter.gyroDictionaries?.first?.layerName, "Particles")
        XCTAssertEqual(imported.documents[.floating]?.stateOverrides["Locked"]?.first?.value, .number(0.25))
        XCTAssertEqual(imported.documents[.floating]?.stateTransitions.first?.fromState, "Locked")
        XCTAssertEqual(imported.documents[.floating]?.stateTransitions.first?.elements.first?.animation?.damping, 14)
    }

    func testArchivePreservesSameNamedAssetsPerCADocument() throws {
        var project = CAProjectDocument.blank(name: "Scoped Assets")
        let backgroundBytes = Data([1, 2, 3, 4])
        let floatingBytes = Data([9, 8, 7, 6])
        project.setAsset(backgroundBytes, named: "shared.png", in: .background)
        project.setAsset(floatingBytes, named: "shared.png", in: .floating)

        let archive = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
        let entries = try ZIPArchive.extract(archive)
        XCTAssertEqual(entries.first(where: { $0.path == "Background.ca/assets/shared.png" })?.data, backgroundBytes)
        XCTAssertEqual(entries.first(where: { $0.path == "Floating.ca/assets/shared.png" })?.data, floatingBytes)

        let imported = try CAArchiveImporter.importProject(data: archive, suggestedName: "Scoped.ca")
        XCTAssertEqual(imported.documentAssets[.background]?["shared.png"], backgroundBytes)
        XCTAssertEqual(imported.documentAssets[.floating]?["shared.png"], floatingBytes)
        XCTAssertEqual(imported.assets(for: .background)["shared.png"], backgroundBytes)
        XCTAssertEqual(imported.assets(for: .floating)["shared.png"], floatingBytes)
    }

    func testLegacyFlatAssetsRemainAvailableToEveryCA() {
        var project = CAProjectDocument.blank()
        let bytes = Data([4, 2])
        project.assets["legacy.png"] = bytes
        XCTAssertEqual(project.assets(for: .background)["legacy.png"], bytes)
        XCTAssertEqual(project.assets(for: .floating)["legacy.png"], bytes)
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

    func testVideoStateSyncArchiveRoundTripPreservesFrameChildrenAndOverrides() throws {
        var project = CAProjectDocument.blank(name: "Video Sync")
        let videoID = UUID()
        let frame0 = UUID()
        let frame1 = UUID()
        var first = LayerModel(id: frame0, name: "frame_0", kind: .image,
                               position: .init(x: 50, y: 50), size: .init(width: 100, height: 100))
        first.imageName = "clip_0.jpg"
        first.zPosition = 0
        var second = LayerModel(id: frame1, name: "frame_1", kind: .image,
                                position: .init(x: 50, y: 50), size: .init(width: 100, height: 100))
        second.imageName = "clip_1.jpg"
        second.zPosition = -1
        var video = LayerModel(id: videoID, name: "Clip", kind: .video, children: [first, second],
                               position: .init(x: 100, y: 100), size: .init(width: 100, height: 100))
        video.framePrefix = "clip_"
        video.frameExtension = ".jpg"
        video.frameCount = 2
        video.framesPerSecond = 30
        video.videoDuration = 2.0 / 30.0
        video.calculationMode = "discrete"
        video.syncWithState = true
        video.syncStateFrameMode = ["Locked": "beginning", "Unlock": "end", "Sleep": "beginning"]
        project.root.children = [video]
        project.setAsset(Data([1, 2, 3]), named: "clip_0.jpg", in: .floating)
        project.setAsset(Data([4, 5, 6]), named: "clip_1.jpg", in: .floating)
        project.stateOverrides = [
            "Locked": [
                .init(targetID: frame0, keyPath: "zPosition", value: .number(0)),
                .init(targetID: frame1, keyPath: "zPosition", value: .number(-1))
            ],
            "Unlock": [
                .init(targetID: frame0, keyPath: "zPosition", value: .number(0)),
                .init(targetID: frame1, keyPath: "zPosition", value: .number(1))
            ],
            "Sleep": [
                .init(targetID: frame0, keyPath: "zPosition", value: .number(0)),
                .init(targetID: frame1, keyPath: "zPosition", value: .number(-1))
            ]
        ]

        let archive = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
        let entries = try ZIPArchive.extract(archive)
        let caml = try XCTUnwrap(entries.first(where: { $0.path == "Floating.ca/main.caml" }))
        let xml = try XCTUnwrap(String(data: caml.data, encoding: .utf8))
        XCTAssertTrue(xml.contains("caplaySyncWWithState=\"1\""))
        XCTAssertTrue(xml.contains(frame0.uuidString))
        XCTAssertTrue(xml.contains(frame1.uuidString))
        XCTAssertFalse(xml.contains("keyPath=\"contents\""))

        let imported = try CAArchiveImporter.importProject(data: archive, suggestedName: "Video Sync.ca")
        let importedVideo = try XCTUnwrap(imported.documents[.floating]?.root.find(id: videoID))
        XCTAssertEqual(importedVideo.syncWithState, true)
        XCTAssertEqual(importedVideo.children.map(\.id), [frame0, frame1])
        XCTAssertEqual(importedVideo.syncStateFrameMode?["Unlock"], "end")
        XCTAssertEqual(imported.documents[.floating]?.stateOverrides["Unlock"]?.first(where: { $0.targetID == frame1 && $0.keyPath == "zPosition" })?.value, .number(1))
    }

    func testGyroWallpaperStyleArchiveRoundTripPreservesParallaxAndPropertyGroups() throws {
        let rootID = UUID()
        let backgroundID = UUID()
        let transformID = UUID()
        var transform = LayerModel(id: transformID, name: "Tilt Layer", kind: .transform,
                                   position: .init(x: 195, y: 422), size: .init(width: 390, height: 844))
        transform.gyroDictionaries = [
            GyroDictionaryModel(axis: "x", keyPath: "position.x", layerName: "Tilt Layer",
                                mapMinTo: -50, mapMaxTo: 50, title: "New Gyro Effect", view: "Wallpaper")
        ]
        let background = LayerModel(id: backgroundID, name: "BACKGROUND", kind: .transform, children: [transform],
                                    position: .init(x: 195, y: 422), size: .init(width: 390, height: 844))
        let floating = LayerModel(id: UUID(), name: "FLOATING", kind: .transform,
                                  position: .init(x: 195, y: 422), size: .init(width: 390, height: 844))
        let root = LayerModel(id: rootID, name: "Root Layer", kind: .basic, children: [background, floating],
                              position: .init(x: 195, y: 422), size: .init(width: 390, height: 844))
        let document = AnimationDocument(
            root: root,
            states: ["Locked", "Unlock", "Sleep"],
            activeState: "Base State",
            stateOverrides: [
                "Locked": [.init(targetID: transformID, keyPath: "position.x", value: .number(120))],
                "Unlock": [.init(targetID: transformID, keyPath: "position.x", value: .number(195))],
                "Sleep": [.init(targetID: transformID, keyPath: "position.x", value: .number(160))]
            ]
        )
        var project = CAProjectDocument(
            id: UUID(), name: "Gyro", width: 390, height: 844, background: "#E5E7EB",
            geometryFlipped: false, gyroEnabled: true, activeCA: .wallpaper,
            documents: [.wallpaper: document], modifiedAt: .now
        )
        project.setAsset(Data([9, 9]), named: "dummy.png", in: .wallpaper)

        let archive = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
        let entries = try ZIPArchive.extract(archive)
        let caml = try XCTUnwrap(entries.first(where: { $0.path == "Wallpaper.ca/main.caml" }))
        let xml = try XCTUnwrap(String(data: caml.data, encoding: .utf8))
        XCTAssertTrue(xml.contains("<wallpaperBackgroundAssetNames type=\"NSArray\"/>"))
        XCTAssertTrue(xml.contains("<wallpaperFloatingAssetNames type=\"NSArray\"/>"))
        XCTAssertTrue(xml.contains("<wallpaperParallaxGroups type=\"NSArray\">"))
        XCTAssertTrue(xml.contains("<wallpaperPropertyGroups type=\"NSArray\">"))
        XCTAssertTrue(xml.contains("<layerName type=\"string\" value=\"Tilt Layer\"/>"))
        XCTAssertTrue(xml.contains("<view type=\"string\" value=\"Background\"/>"))

        let imported = try CAArchiveImporter.importProject(data: archive, suggestedName: "Gyro.ca")
        let importedTransform = try XCTUnwrap(imported.documents[.wallpaper]?.root.find(id: transformID))
        XCTAssertEqual(importedTransform.gyroDictionaries?.first?.layerName, "Tilt Layer")
        XCTAssertEqual(importedTransform.gyroDictionaries?.first?.keyPath, "position.x")
        XCTAssertEqual(imported.documents[.wallpaper]?.stateOverrides["Locked"]?.first(where: { $0.targetID == transformID && $0.keyPath == "position.x" })?.value, .number(120))
        XCTAssertEqual(imported.documents[.wallpaper]?.stateOverrides["Unlock"]?.first(where: { $0.targetID == transformID && $0.keyPath == "position.x" })?.value, .number(195))
        XCTAssertEqual(imported.documents[.wallpaper]?.stateOverrides["Sleep"]?.first(where: { $0.targetID == transformID && $0.keyPath == "position.x" })?.value, .number(160))
    }


    func testStateExportFillsCounterpartOverridesAndDefaultTransitions() {
        var project = CAProjectDocument.blank(name: "State Parity")
        let layerID = UUID()
        var layer = LayerModel(id: layerID, name: "State Layer", kind: .basic,
                               position: .init(x: 100, y: 200), size: .init(width: 80, height: 90))
        layer.opacity = 1
        project.root.children = [layer]
        project.states = ["Locked", "Unlock", "Sleep"]
        project.stateOverrides = [
            "Locked": [.init(targetID: layerID, keyPath: "opacity", value: .number(0.25))]
        ]
        project.stateTransitions = []

        let xml = CAMLSerializer.serialize(project: project, document: project.documents[.floating]!, kind: .floating)
        let overrideMarker = "targetId=\"\(layerID.uuidString)\" keyPath=\"opacity\""
        XCTAssertEqual(xml.components(separatedBy: overrideMarker).count - 1, 3)
        XCTAssertTrue(xml.contains("<value type=\"real\" value=\"0.25\"/>"))
        XCTAssertGreaterThanOrEqual(xml.components(separatedBy: "<value type=\"integer\" value=\"1\"/>").count - 1, 2)
        XCTAssertTrue(xml.contains("fromState=\"*\" toState=\"Unlock\""))
        XCTAssertTrue(xml.contains("fromState=\"Unlock\" toState=\"*\""))
        XCTAssertTrue(xml.contains("fromState=\"*\" toState=\"Locked\""))
        XCTAssertTrue(xml.contains("fromState=\"Locked\" toState=\"*\""))
        XCTAssertTrue(xml.contains("fromState=\"*\" toState=\"Sleep\""))
        XCTAssertTrue(xml.contains("fromState=\"Sleep\" toState=\"*\""))
    }


    func testFilterNamesAndParameterlessInvertRoundTrip() throws {
        var project = CAProjectDocument.blank(name: "Filters")
        let layerID = UUID()
        var layer = LayerModel(id: layerID, name: "Filtered", kind: .basic,
                               position: .init(x: 100, y: 100), size: .init(width: 100, height: 100))
        layer.filters = [
            FilterModel(type: "gaussianBlur", name: "Gaussian Blur 1", value: 10),
            FilterModel(type: "gaussianBlur", name: "Gaussian Blur 2", value: 20),
            FilterModel(type: "colorInvert", name: "Invert 1", value: 0)
        ]
        project.root.children = [layer]

        let archive = try CAArchiveExporter.export(project: project, format: .ca, license: .none)
        let entries = try ZIPArchive.extract(archive)
        let caml = try XCTUnwrap(entries.first(where: { $0.path == "Floating.ca/main.caml" }))
        let xml = try XCTUnwrap(String(data: caml.data, encoding: .utf8))
        XCTAssertTrue(xml.contains("name=\"Gaussian Blur 1\""))
        XCTAssertTrue(xml.contains("name=\"Gaussian Blur 2\""))
        XCTAssertTrue(xml.contains("filter=\"colorInvert\" name=\"Invert 1\" enabled=\"true\"/>"))
        XCTAssertFalse(xml.contains("filter=\"colorInvert\" name=\"Invert 1\" enabled=\"true\" inputAmount"))

        let imported = try CAArchiveImporter.importProject(data: archive, suggestedName: "Filters.ca")
        let importedLayer = try XCTUnwrap(imported.documents[.floating]?.root.find(id: layerID))
        XCTAssertEqual(importedLayer.filters.map(\.name), ["Gaussian Blur 1", "Gaussian Blur 2", "Invert 1"])
        XCTAssertEqual(importedLayer.filters.last?.value, 0)
    }

}
