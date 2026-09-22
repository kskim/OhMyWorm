import Foundation

/// Same 11→6→2 structure as ``MiniBrain``, but its hand-designed weights
/// are scaled by aggregate statistics of the real C. elegans connectome
/// (cook2019-herm-corrected2020-openworm: 302 neurons, 4814 records).
/// This is a game model, NOT a simulation of the real network.
///
/// Baked scaling factors (MODEL choices, derived offline):
/// - SENSORY = 1.148: sensory-role mean out-weight ÷ global mean.
///   Scales the steering input rows (h0/h1/h2) and their turn outputs.
/// - MOTOR = 0.846: motor-role mean in-weight ÷ global mean.
///   Scales the drive row (h3) and the speed output.
/// - MEMORY = 1.216: 1 + gap-junction weight fraction (0.216).
///   Scales the recurrent diagonal (h0–h3).
/// - The h4/h5 oscillator is a pure game construct and stays identical.
struct MediumBrain: LocomotionEngine {
    static let sensoryScale = 1.148
    static let motorScale = 0.846
    static let memoryScale = 1.216

    /// Rows: hidden units h0..h5. Columns: MiniBrain.Sensor order.
    static let inputWeights: [[Double]] = [
        [1.722, -1.722, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 1.378, -1.378, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 2.296, -2.296, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.846, 0.0, 0.0, 0.0, 0.0, -0.846, 0.677, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.6],
    ]

    /// Recurrent weights: rows/cols are hidden units h0..h5.
    static let recurrentWeights: [[Double]] = [
        [0.730, 0.0, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.486, 0.0, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.365, 0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.608, 0.0, 0.0],
        [0.0, 0.0, 0.0, 0.0, 0.2, 0.9],
        [0.0, 0.0, 0.0, 0.0, -0.9, 0.2],
    ]

    /// Rows: turn, speed. Columns: hidden units h0..h5.
    static let outputWeights: [[Double]] = [
        [1.378, 1.033, -1.837, 0.0, 0.55, 0.0],
        [0.0, 0.0, 0.0, 1.015, 0.0, 0.0],
    ]
    static let outputBias: [Double] = [0.0, 0.8]

    var hidden: [Double] = [0, 0, 0, 0, 0, 0]

    /// Advance one step. Returns turn in [-1, 1] (positive = left/CCW)
    /// and speed in [0, 1].
    mutating func step(_ inputs: [Double]) -> (turn: Double, speed: Double) {
        precondition(inputs.count == MiniBrain.Sensor.count)
        var next = [Double](repeating: 0, count: MiniBrain.hiddenCount)
        for h in 0..<MiniBrain.hiddenCount {
            var sum = 0.0
            for i in 0..<MiniBrain.Sensor.count { sum += Self.inputWeights[h][i] * inputs[i] }
            for j in 0..<MiniBrain.hiddenCount { sum += Self.recurrentWeights[h][j] * hidden[j] }
            next[h] = tanh(sum)
        }
        hidden = next
        var turn = Self.outputBias[0]
        var drive = Self.outputBias[1]
        for j in 0..<MiniBrain.hiddenCount {
            turn += Self.outputWeights[0][j] * hidden[j]
            drive += Self.outputWeights[1][j] * hidden[j]
        }
        return (tanh(turn), 1.0 / (1.0 + exp(-drive)))
    }
}
