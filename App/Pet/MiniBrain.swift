import Foundation

/// A hand-wired miniature recurrent rate network that drives locomotion.
/// This is a game model, NOT the real C. elegans connectome.
///
/// - 13 sensory inputs (see ``Sensor``)
/// - 6 recurrent tanh hidden units (food / edge / wall / drive / oscillator pair)
/// - 2 outputs: turn rate in [-1, 1] and speed in [0, 1]
struct MiniBrain: LocomotionEngine {
    enum Sensor: Int {
        case foodLeft, foodRight, foodProximity
        case edgeLeft, edgeRight
        case wallLeft, wallRight, wallNear
        case hunger
        case cpg1, cpg2
        case cursorLeft, cursorRight

        static let count = 13
    }

    static let hiddenCount = 6

    /// Rows: hidden units h0..h5. Columns: Sensor order.
    /// h0 food steering, h1 edge steering, h2 wall/cursor avoidance,
    /// h3 approach drive, h4/h5 exploratory oscillator pair.
    static let inputWeights: [[Double]] = [
        [1.5, -1.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 1.2, -1.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 2.0, -2.0, 0.0, 0.0, 0.0, 0.0, 2.0, -2.0],
        [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.8, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.0, 0.0],
    ]

    /// Recurrent weights: rows/cols are hidden units h0..h5.
    /// h4/h5 cross-coupling forms the exploratory oscillator.
    static let recurrentWeights: [[Double]] = [
        [0.6, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.4, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.3, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.5, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.2, 0.9],
        [0.0, 0.0, 0.0, 0.0, -0.9, 0.2],
    ]

    /// Rows: turn, speed. Columns: hidden units h0..h5.
    static let outputWeights: [[Double]] = [
        [1.2, 0.9, -1.6, 0.0, 0.55, 0.0],
        [0.0, 0.0, 0.0, 1.2, 0.0, 0.0],
    ]
    static let outputBias: [Double] = [0.0, 0.8]

    var hidden: [Double] = [0, 0, 0, 0, 0, 0]

    /// Advance one step. Returns turn in [-1, 1] (positive = left/CCW)
    /// and speed in [0, 1].
    mutating func step(_ inputs: [Double]) -> (turn: Double, speed: Double) {
        precondition(inputs.count == Sensor.count)
        var next = [Double](repeating: 0, count: Self.hiddenCount)
        for h in 0..<Self.hiddenCount {
            var sum = 0.0
            for i in 0..<Sensor.count { sum += Self.inputWeights[h][i] * inputs[i] }
            for j in 0..<Self.hiddenCount { sum += Self.recurrentWeights[h][j] * hidden[j] }
            next[h] = tanh(sum)
        }
        hidden = next
        var turn = Self.outputBias[0]
        var drive = Self.outputBias[1]
        for j in 0..<Self.hiddenCount {
            turn += Self.outputWeights[0][j] * hidden[j]
            drive += Self.outputWeights[1][j] * hidden[j]
        }
        return (tanh(turn), 1.0 / (1.0 + exp(-drive)))
    }
}
