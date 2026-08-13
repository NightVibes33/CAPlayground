from pathlib import Path
import re

serializer = Path('apps/ios/CAPlayground/Export/CAMLSerializer.swift')
s = serializer.read_text()
pattern = re.compile(r'''    private static func states\(_ document: AnimationDocument\) -> String \{.*?\n    \}\n\n    private static func emitterCells''', re.S)
replacement = r'''    private static func states(_ document: AnimationDocument) -> String {
        let filtered = document.states.filter { !$0.lowercased().hasPrefix("base") }
        let names = filtered.isEmpty ? ["Locked", "Unlock", "Sleep"] : filtered
        let normalized = normalizedStateOverrides(document, names: names)
        let stateXML = names.map { name in
            let overrides = normalized[name] ?? []
            let elements = overrides.map { value in
                let encoded: (String, String) = switch value.value {
                case .number(let valueNumber):
                    if value.keyPath == "position.x" || value.keyPath == "position.y" {
                        ("integer", number(valueNumber.rounded()))
                    } else {
                        let converted = value.keyPath.hasPrefix("transform.rotation") ? valueNumber * .pi / 180 : valueNumber
                        (converted.rounded() == converted ? "integer" : "real", number(converted))
                    }
                case .string(let string):
                    (value.keyPath == "backgroundColor" ? "CGColor" : "string", value.keyPath == "backgroundColor" ? (color(string) ?? "1 1 1") : string)
                }
                return "        <LKStateSetValue targetId=\"\(value.targetID.uuidString)\" keyPath=\"\(escape(value.keyPath))\"><value type=\"\(encoded.0)\" value=\"\(escape(encoded.1))\"/></LKStateSetValue>"
            }.joined(separator: "\n")
            return "    <LKState name=\"\(escape(name))\"><elements>\n\(elements)\n      </elements></LKState>"
        }.joined(separator: "\n")

        let transitions = document.stateTransitions.isEmpty ? defaultStateTransitions() : document.stateTransitions
        let transitionXML = transitions.map { transition in
            let elements = transition.elements.map { element in
                guard let spring = element.animation else { return "        <LKStateTransitionElement targetId=\"\(element.targetID.uuidString)\" key=\"\(escape(element.keyPath))\"/>" }
                var attrs = "type=\"\(escape(spring.type))\" damping=\"\(number(spring.damping))\" mass=\"\(number(spring.mass))\" stiffness=\"\(number(spring.stiffness))\" velocity=\"\(number(spring.initialVelocity))\""
                if let duration = spring.duration { attrs += " duration=\"\(number(duration))\"" }
                if let fillMode = spring.fillMode { attrs += " fillMode=\"\(escape(fillMode))\"" }
                if let keyPath = spring.keyPath { attrs += " keyPath=\"\(escape(keyPath))\"" }
                if let recalculates = spring.micaAutorecalculatesDuration { attrs += " mica_autorecalculatesDuration=\"\(recalculates ? "1" : "0")\"" }
                return "        <LKStateTransitionElement targetId=\"\(element.targetID.uuidString)\" key=\"\(escape(element.keyPath))\"><animation \(attrs)/></LKStateTransitionElement>"
            }.joined(separator: "\n")
            return "    <LKStateTransition fromState=\"\(escape(transition.fromState))\" toState=\"\(escape(transition.toState))\"><elements>\n\(elements)\n      </elements></LKStateTransition>"
        }.joined(separator: "\n")
        return "\n    <states>\n\(stateXML)\n    </states>\n    <stateTransitions>\n\(transitionXML)\n    </stateTransitions>"
    }

    private static func normalizedStateOverrides(_ document: AnimationDocument, names: [String]) -> [String: [StateOverride]] {
        var result = document.stateOverrides
        var keys: [(UUID, String)] = []
        for name in names {
            for override in result[name] ?? [] where !keys.contains(where: { $0.0 == override.targetID && $0.1 == override.keyPath }) {
                keys.append((override.targetID, override.keyPath))
            }
        }
        for (targetID, keyPath) in keys {
            guard let fallback = baseStateValue(root: document.root, targetID: targetID, keyPath: keyPath) else { continue }
            for name in names {
                var values = result[name] ?? []
                if !values.contains(where: { $0.targetID == targetID && $0.keyPath == keyPath }) {
                    values.append(.init(targetID: targetID, keyPath: keyPath, value: fallback))
                    result[name] = values
                }
            }
        }
        return result
    }

    private static func baseStateValue(root: LayerModel, targetID: UUID, keyPath: String) -> OverrideValue? {
        guard let layer = root.find(id: targetID) else { return nil }
        return switch keyPath {
        case "position.x": .number(layer.position.x)
        case "position.y": .number(layer.position.y)
        case "zPosition": .number(layer.zPosition)
        case "bounds.size.width": .number(layer.size.width)
        case "bounds.size.height": .number(layer.size.height)
        case "transform.scale.xy": .number(layer.scale)
        case "transform.rotation.z": .number(layer.rotation)
        case "transform.rotation.x": .number(layer.rotationX)
        case "transform.rotation.y": .number(layer.rotationY)
        case "opacity": .number(layer.opacity)
        case "cornerRadius": .number(layer.cornerRadius)
        case "backgroundColor": .string(layer.backgroundColor ?? "#FFFFFF")
        default: nil
        }
    }

    private static func defaultStateTransitions() -> [StateTransition] {
        [
            .init(fromState: "*", toState: "Unlock", elements: []),
            .init(fromState: "Unlock", toState: "*", elements: []),
            .init(fromState: "*", toState: "Locked", elements: []),
            .init(fromState: "Locked", toState: "*", elements: []),
            .init(fromState: "*", toState: "Sleep", elements: []),
            .init(fromState: "Sleep", toState: "*", elements: [])
        ]
    }

    private static func emitterCells'''
s2, count = pattern.subn(replacement, s, count=1)
if count != 1:
    raise SystemExit(f'states replacement count={count}')
serializer.write_text(s2)

tests = Path('apps/ios/CAPlaygroundTests/ModelTests.swift')
t = tests.read_text()
insert_at = t.rfind('\n}')
if insert_at < 0:
    raise SystemExit('test class closing brace not found')
new_test = r'''

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
'''
tests.write_text(t[:insert_at] + new_test + t[insert_at:])

Path('.github/state_export_patch.py').unlink()
Path('.github/workflows/state-export-parity.yml').unlink()
