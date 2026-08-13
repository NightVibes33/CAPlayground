from pathlib import Path

# Preserve legacy nested gyro dictionaries for non-wallpaper CA only.
serializer = Path('apps/ios/CAPlayground/Export/CAMLSerializer.swift')
s = serializer.read_text()
replacements = [
    (
        'let serializedRoot = wallpaper ? layer(document.root, indent: 1, rootStyle: rootStyle) : wrapper(root: document.root)',
        'let serializedRoot = wallpaper ? layer(document.root, indent: 1, rootStyle: rootStyle, includeLayerGyroStyle: false) : wrapper(root: document.root)'
    ),
    (
        'private static func layer(_ model: LayerModel, indent: Int, rootStyle: String? = nil) -> String {',
        'private static func layer(_ model: LayerModel, indent: Int, rootStyle: String? = nil, includeLayerGyroStyle: Bool = true) -> String {'
    ),
    (
        'if let rootStyle { children += rootStyle }\n        if !model.children.isEmpty { children += "\\n\\(pad)  <sublayers>" + model.children.map { "\\n" + layer($0, indent: indent + 2) }.joined() + "\\n\\(pad)  </sublayers>" }',
        'if includeLayerGyroStyle, let gyro = model.gyroDictionaries, !gyro.isEmpty { children += legacyLayerGyroStyle(gyro, indent: indent + 1) }\n        if let rootStyle { children += rootStyle }\n        if !model.children.isEmpty { children += "\\n\\(pad)  <sublayers>" + model.children.map { "\\n" + layer($0, indent: indent + 2, includeLayerGyroStyle: includeLayerGyroStyle) }.joined() + "\\n\\(pad)  </sublayers>" }'
    ),
]
for old, new in replacements:
    if s.count(old) != 1:
        raise SystemExit(f'serializer compatibility marker count={s.count(old)}: {old[:80]!r}')
    s = s.replace(old, new, 1)

marker = '    private static func wallpaperStyle(\n'
legacy = r'''    private static func legacyLayerGyroStyle(_ dictionaries: [GyroDictionaryModel], indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        let items = dictionaries.map { item in
            "\n\(pad)    <NSDictionary>" +
            "<axis type=\"string\" value=\"\(escape(item.axis))\"/>" +
            "<image type=\"string\" value=\"null\"/>" +
            "<keyPath type=\"string\" value=\"\(escape(item.keyPath))\"/>" +
            "<layerName type=\"string\" value=\"\(escape(item.layerName))\"/>" +
            "<mapMaxTo type=\"real\" value=\"\(number(item.mapMaxTo))\"/>" +
            "<mapMinTo type=\"real\" value=\"\(number(item.mapMinTo))\"/>" +
            "<title type=\"string\" value=\"\(escape(item.title))\"/>" +
            "<view type=\"string\" value=\"\(escape(item.view))\"/>" +
            "</NSDictionary>"
        }.joined()
        return "\n\(pad)<style>\n\(pad)  <wallpaperParallaxGroups type=\"NSArray\">\(items)\n\(pad)  </wallpaperParallaxGroups>\n\(pad)</style>"
    }

'''
if s.count(marker) != 1:
    raise SystemExit(f'wallpaperStyle marker count={s.count(marker)}')
s = s.replace(marker, legacy + marker, 1)
serializer.write_text(s)

# Add semantic round-trip tests to the existing test target.
tests = Path('apps/ios/CAPlaygroundTests/ModelTests.swift')
t = tests.read_text()
insert_at = t.rfind('\n}')
if insert_at < 0:
    raise SystemExit('could not find ModelTests class closing brace')
new_tests = r'''

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
'''
tests.write_text(t[:insert_at] + new_tests + t[insert_at:])

Path('.github/roundtrip_tests_patch.py').unlink()
Path('.github/workflows/roundtrip-tests-parity.yml').unlink()
