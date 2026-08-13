from pathlib import Path

path = Path('apps/ios/CAPlayground/Export/CAMLSerializer.swift')
s = path.read_text()

def replace_between(source: str, start_marker: str, end_marker: str, block: str) -> str:
    start = source.find(start_marker)
    if start < 0:
        raise SystemExit(f'missing start marker: {start_marker}')
    end = source.find(end_marker, start)
    if end < 0:
        raise SystemExit(f'missing end marker: {end_marker}')
    return source[:start] + block + source[end:]

filters_block = r'''    private static func filters(_ filters: [FilterModel], indent: Int) -> String {
        let pad = String(repeating: "  ", count: indent)
        var counts: [String: Int] = [:]
        let items = filters.map { filter -> String in
            counts[filter.type, default: 0] += 1
            let exportName = filter.name ?? "\(filterDisplayName(filter.type)) \(counts[filter.type] ?? 1)"
            let enabled = filter.enabled ? "true" : "false"
            switch filter.type {
            case "gaussianBlur":
                return "\n\(pad)  <CAFilter filter=\"gaussianBlur\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\" inputRadius=\"\(number(filter.value))\"/>"
            case "colorContrast", "colorSaturate":
                return "\n\(pad)  <CAFilter filter=\"\(escape(filter.type))\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\" inputAmount=\"\(number(filter.value))\"/>"
            case "colorHueRotate":
                return "\n\(pad)  <CAFilter filter=\"colorHueRotate\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\" inputAngle=\"\(number(filter.value * .pi / 180))\"/>"
            case "colorInvert":
                return "\n\(pad)  <CAFilter filter=\"colorInvert\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\"/>"
            case "CISepiaTone":
                return "\n\(pad)  <CIFilter filter=\"CISepiaTone\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\"><inputIntensity type=\"real\" value=\"\(number(filter.value))\"/></CIFilter>"
            default:
                return "\n\(pad)  <CAFilter filter=\"\(escape(filter.type))\" name=\"\(escape(exportName))\" enabled=\"\(enabled)\"/>"
            }
        }.joined()
        return "\n\(pad)<filters>\(items)\n\(pad)</filters>"
    }

'''

states_block = r'''    private static func states(_ document: AnimationDocument) -> String {
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
                    (
                        value.keyPath == "backgroundColor" ? "CGColor" : "string",
                        value.keyPath == "backgroundColor" ? (color(string) ?? "1 1 1") : string
                    )
                }
                return "        <LKStateSetValue targetId=\"\(value.targetID.uuidString)\" keyPath=\"\(escape(value.keyPath))\"><value type=\"\(encoded.0)\" value=\"\(escape(encoded.1))\"/></LKStateSetValue>"
            }.joined(separator: "\n")
            return "    <LKState name=\"\(escape(name))\"><elements>\n\(elements)\n      </elements></LKState>"
        }.joined(separator: "\n")

        let transitions = document.stateTransitions.isEmpty ? defaultStateTransitions() : document.stateTransitions
        let transitionXML = transitions.map { transition in
            let elements = transition.elements.map { element in
                guard let spring = element.animation else {
                    return "        <LKStateTransitionElement targetId=\"\(element.targetID.uuidString)\" key=\"\(escape(element.keyPath))\"/>"
                }
                var attrs = "type=\"\(escape(spring.type))\" damping=\"\(number(spring.damping))\" mass=\"\(number(spring.mass))\" stiffness=\"\(number(spring.stiffness))\" velocity=\"\(number(spring.initialVelocity))\""
                if let duration = spring.duration { attrs += " duration=\"\(number(duration))\"" }
                if let fillMode = spring.fillMode { attrs += " fillMode=\"\(escape(fillMode))\"" }
                if let keyPath = spring.keyPath { attrs += " keyPath=\"\(escape(keyPath))\"" }
                if let recalculates = spring.micaAutorecalculatesDuration {
                    attrs += " mica_autorecalculatesDuration=\"\(recalculates ? "1" : "0")\""
                }
                return "        <LKStateTransitionElement targetId=\"\(element.targetID.uuidString)\" key=\"\(escape(element.keyPath))\"><animation \(attrs)/></LKStateTransitionElement>"
            }.joined(separator: "\n")
            return "    <LKStateTransition fromState=\"\(escape(transition.fromState))\" toState=\"\(escape(transition.toState))\"><elements>\n\(elements)\n      </elements></LKStateTransition>"
        }.joined(separator: "\n")

        return "\n    <states>\n\(stateXML)\n    </states>\n    <stateTransitions>\n\(transitionXML)\n    </stateTransitions>"
    }

'''

s = replace_between(
    s,
    '    private static func filters(_ filters: [FilterModel], indent: Int) -> String {',
    '    private static func filterDisplayName(_ type: String) -> String {',
    filters_block,
)
s = replace_between(
    s,
    '    private static func states(_ document: AnimationDocument) -> String {',
    '    private static func normalizedStateOverrides(_ document: AnimationDocument, names: [String]) -> [String: [StateOverride]] {',
    states_block,
)
path.write_text(s)
Path('.github/fix_serializer_strings.py').unlink()
Path('.github/workflows/fix-serializer-strings.yml').unlink()
