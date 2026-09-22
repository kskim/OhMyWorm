import Foundation

/// Selectable locomotion brains.
enum EngineID: String, CaseIterable, Identifiable, Sendable {
    case light
    case medium
    case real

    var id: String { rawValue }

    init?(storedValue: String) {
        if storedValue == "hard" { self = .real; return } // renamed in 0.3
        self.init(rawValue: storedValue)
    }

    var displayName: String {
        switch self {
        case .light: return "라이트"
        case .medium: return "미디엄"
        case .real: return "리얼"
        }
    }
}

/// Anything that turns the 11-element sensor vector (MiniBrain.Sensor order)
/// into locomotion. Returns turn in [-1, 1] (positive = left/CCW) and
/// speed in [0, 1].
protocol LocomotionEngine: Sendable {
    mutating func step(_ inputs: [Double]) -> (turn: Double, speed: Double)
}

/// The selectable brain inside ``PetModel``.
enum Brain: Sendable {
    case light(MiniBrain)
    case medium(MediumBrain)
    case real(RealBrain)

    var id: EngineID {
        switch self {
        case .light: return .light
        case .medium: return .medium
        case .real: return .real
        }
    }

    mutating func step(_ inputs: [Double]) -> (turn: Double, speed: Double) {
        switch self {
        case .light(var brain):
            let output = brain.step(inputs)
            self = .light(brain)
            return output
        case .medium(var brain):
            let output = brain.step(inputs)
            self = .medium(brain)
            return output
        case .real(var brain):
            let output = brain.step(inputs)
            self = .real(brain)
            return output
        }
    }
}
