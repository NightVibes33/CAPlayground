import Foundation
import CoreGraphics

struct CAProjectDocument: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var width: Double
    var height: Double
    var background: String?
    var geometryFlipped: Bool
    var gyroEnabled: Bool
    var activeCA: CADocumentKind
    var documents: [CADocumentKind: AnimationDocument]
    var modifiedAt: Date

    var root: LayerModel {
        get { documents[activeCA]!.root }
        set { documents[activeCA]!.root = newValue }
    }

    var states: [String] {
        get { documents[activeCA]!.states }
        set { documents[activeCA]!.states = newValue }
    }

    var activeState: String {
        get { documents[activeCA]!.activeState }
        set { documents[activeCA]!.activeState = newValue }
    }

    var stateOverrides: [String: [StateOverride]] {
        get { documents[activeCA]!.stateOverrides }
        set { documents[activeCA]!.stateOverrides = newValue }
    }

    var stateTransitions: [StateTransition] {
        get { documents[activeCA]!.stateTransitions }
        set { documents[activeCA]!.stateTransitions = newValue }
    }

    static func blank(name: String = "Untitled Wallpaper") -> Self {
        func root(_ name: String) -> LayerModel {
            LayerModel(
                id: UUID(), name: name, kind: .basic,
                position: .init(x: 195, y: 422), size: .init(width: 390, height: 844),
                backgroundColor: "#E5E7EB", geometryFlipped: false
            )
        }
        let floating = AnimationDocument(root: root("Root Layer"))
        let background = AnimationDocument(root: root("Root Layer"))
        return .init(
            id: UUID(), name: name, width: 390, height: 844,
            background: "#E5E7EB", geometryFlipped: false,
            gyroEnabled: false, activeCA: .floating,
            documents: [.floating: floating, .background: background], modifiedAt: .now
        )
    }
}

enum CADocumentKind: String, Codable, CaseIterable, Hashable, Identifiable {
    case floating, background, wallpaper
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AnimationDocument: Codable, Hashable {
    var root: LayerModel
    var states: [String] = ["Locked", "Unlock", "Sleep"]
    var activeState: String = "Base State"
    var stateOverrides: [String: [StateOverride]] = [:]
    var stateTransitions: [StateTransition] = []
    var selectedID: UUID?
    var appearanceMode = "light"
    var appearanceSplit = false
}

struct Vector2: Codable, Hashable {
    var x: Double
    var y: Double
}

struct LayerSize: Codable, Hashable {
    var width: Double
    var height: Double
}

enum LayerKind: String, Codable, CaseIterable, Identifiable {
    case basic, shape, image, text, gradient, video, emitter, transform, replicator, liquidGlass
    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .basic: "square"
        case .shape: "circle.square"
        case .image: "photo"
        case .text: "textformat"
        case .gradient: "circle.lefthalf.filled"
        case .video: "film"
        case .emitter: "sparkles"
        case .transform: "move.3d"
        case .replicator: "square.on.square"
        case .liquidGlass: "drop"
        }
    }
}

struct GradientStop: Codable, Hashable {
    var color: String
    var opacity: Double
}

struct FilterModel: Codable, Hashable, Identifiable {
    var id = UUID()
    var type: String
    var value: Double
    var enabled = true
}

struct EmitterCellModel: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = "Particle"
    var imageName: String?
    var birthRate = 18.0
    var lifetime = 2.5
    var lifetimeRange = 0.0
    var velocity = 45.0
    var velocityRange = 25.0
    var emissionLongitude = 0.0
    var emissionLatitude = 0.0
    var emissionRange = 360.0
    var scale = 0.03
    var scaleRange = 0.02
    var scaleSpeed = 0.0
    var alphaRange = 0.0
    var alphaSpeed = -0.35
    var spin = 0.0
    var spinRange = 0.0
    var xAcceleration = 0.0
    var yAcceleration = 0.0
    var color = "#FFFFFF"
}

struct GyroDictionaryModel: Codable, Hashable, Identifiable {
    var id = UUID()
    var axis = "x"
    var keyPath = "position.x"
    var layerName: String
    var mapMinTo = -50.0
    var mapMaxTo = 50.0
    var title = "Tilt Effect"
    var view = "Wallpaper"
}

struct KeyframeAnimationModel: Codable, Hashable, Identifiable {
    var id = UUID()
    var enabled = true
    var keyPath: String
    var numericValues: [Double]
    var keyTimes: [Double]
    var duration: Double
    var autoreverses = false
    var repeats = true
    var calculationMode = "linear"
    var timingFunction = "linear"
}

struct LayerModel: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var kind: LayerKind
    var children: [LayerModel] = []
    var position: Vector2
    var size: LayerSize
    var zPosition: Double = 0
    var scale: Double = 1
    var speed: Double = 1
    var opacity: Double = 1
    var rotation: Double = 0
    var rotationX: Double = 0
    var rotationY: Double = 0
    var backgroundColor: String?
    var backgroundOpacity: Double = 1
    var borderColor: String?
    var borderWidth: Double = 0
    var cornerRadius: Double = 0
    var isVisible = true
    var anchorPoint = Vector2(x: 0.5, y: 0.5)
    var geometryFlipped = false
    var masksToBounds = false
    var blendMode: String?
    var filters: [FilterModel] = []
    var animations: [KeyframeAnimationModel] = []

    // Type-specific values mirror the web schema without coupling the model to UIKit.
    var text: String?
    var fontFamily: String?
    var fontSize: Double?
    var textColor: String?
    var textAlignment: String?
    var wrapsText: Bool?
    var imageName: String?
    var contentMode: String?
    var shape: String?
    var fillColor: String?
    var strokeColor: String?
    var strokeWidth: Double?
    var gradientType: String?
    var gradientStart: Vector2?
    var gradientEnd: Vector2?
    var gradientStops: [GradientStop]?
    var frameCount: Int?
    var framesPerSecond: Double?
    var calculationMode: String?
    var autoReverses: Bool?
    var syncWithState: Bool?
    var emitterPosition: Vector2?
    var emitterSize: LayerSize?
    var emitterShape: String?
    var emitterMode: String?
    var renderMode: String?
    var emitterCells: [EmitterCellModel]?
    var instanceCount: Int?
    var instanceTranslationX: Double?
    var instanceTranslationY: Double?
    var instanceTranslationZ: Double?
    var instanceRotation: Double?
    var instanceDelay: Double?
    var perspective: Double?
    var gyroDictionaries: [GyroDictionaryModel]?

    var outlineChildren: [LayerModel]? { children.isEmpty ? nil : children }
}

struct StateOverride: Codable, Hashable {
    var targetID: UUID
    var keyPath: String
    var value: OverrideValue
}

enum OverrideValue: Codable, Hashable {
    case number(Double)
    case string(String)
}

struct StateTransition: Codable, Hashable, Identifiable {
    var id = UUID()
    var fromState: String
    var toState: String
    var elements: [StateTransitionElement]
}

struct StateTransitionElement: Codable, Hashable {
    var targetID: UUID
    var keyPath: String
    var animation: SpringAnimationModel?
}

struct SpringAnimationModel: Codable, Hashable {
    var damping: Double = 10
    var mass: Double = 1
    var stiffness: Double = 100
    var initialVelocity: Double = 0
    var duration: Double?
}
