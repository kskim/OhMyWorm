import Foundation

public struct NeuralState: Equatable, Sendable {
    public let activity: [Double]
    public let adaptation: [Double]
    public init(activity: [Double], adaptation: [Double]) {
        self.activity = activity
        self.adaptation = adaptation
    }
}

public struct NeuralInput: Equatable, Sendable {
    public let sensory: [Double]
    public let proprioception: [Double]
    public init(sensory: [Double], proprioception: [Double]) {
        self.sensory = sensory
        self.proprioception = proprioception
    }
    public static func zero(count: Int) -> Self {
        Self(sensory: Array(repeating: 0, count: count), proprioception: Array(repeating: 0, count: count))
    }
}

/// Currents used for the most recent transition, in projection.neuronIDs order.
/// gap is the old-state diffusive current, not a post-step activity difference.
public struct NeuralTrace: Equatable, Sendable {
    public let input: NeuralInput
    public let chemical: [Double]
    public let gap: [Double]
}

/// Concrete bounded rate/adaptation model. No clock, body or behavior state.
public struct NeuralEngine: Sendable {
    public static let timeStep = 1.0 / 120.0
    public let projection: NeuralProjection
    public let parameters: NeuralParameters
    public let experiment: NeuralExperiment
    public private(set) var state: NeuralState
    public private(set) var trace: NeuralTrace
    private let chemical: [NeuralProjection.Edge]
    private let gaps: [NeuralProjection.Edge]
    private let cells: [NeuralCellParameters]
    private let activityFraction: [Double]
    private let adaptationFraction: [Double]

    public init(projection: NeuralProjection, parameters: NeuralParameters = .init(),
                experiment: NeuralExperiment = .init(), initial: NeuralState? = nil) throws {
        try parameters.validate()
        for index in experiment.disabledConnectionIndices.sorted() {
            guard projection.graph.document.connections.indices.contains(index) else {
                throw NeuralError.invalidConnectionIndex(index)
            }
        }
        self.projection = projection
        self.parameters = parameters
        self.experiment = experiment
        let count = projection.neuronIDs.count
        let initial = initial ?? parameters.initialState(neuronIDs: projection.neuronIDs)
        try Self.validate(initial, count: count)
        let zeros = Array(repeating: 0.0, count: count)
        state = experiment.silence ? NeuralState(activity: zeros, adaptation: zeros) : initial
        trace = NeuralTrace(input: .zero(count: count), chemical: zeros, gap: zeros)
        chemical = projection.chemical.filter { !experiment.disabledConnectionIndices.contains($0.connectionIndex) }
        gaps = projection.gaps.filter { !experiment.disabledConnectionIndices.contains($0.connectionIndex) }
        let cells = projection.neuronIDs.map { parameters.cell(for: $0) }
        self.cells = cells
        var degree = zeros
        for edge in gaps {
            degree[edge.sourceIndex] += edge.coefficient
            degree[edge.targetIndex] += edge.coefficient
        }
        activityFraction = cells.indices.map { -expm1(-Self.timeStep * (1 + parameters.gapGain * degree[$0]) / cells[$0].timeConstant) }
        adaptationFraction = cells.map { -expm1(-Self.timeStep / $0.adaptationTimeConstant) }
    }

    public mutating func reset(to initial: NeuralState? = nil) throws {
        let initial = initial ?? parameters.initialState(neuronIDs: projection.neuronIDs)
        try Self.validate(initial, count: projection.neuronIDs.count)
        let zeros = Array(repeating: 0.0, count: projection.neuronIDs.count)
        state = experiment.silence ? NeuralState(activity: zeros, adaptation: zeros) : initial
        trace = NeuralTrace(input: .zero(count: zeros.count), chemical: zeros, gap: zeros)
    }

    public mutating func step(input: NeuralInput) throws {
        let count = projection.neuronIDs.count
        // The public current boundary rejects malformed values before mutation.
        // 1e6 is a numerical input limit in model units, not a biological limit.
        guard input.sensory.count == count, input.proprioception.count == count,
              input.sensory.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
              input.proprioception.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 })
        else { throw NeuralError.invalidInput }
        var chemicalCurrent = Array(repeating: 0.0, count: count)
        var gapCurrent = chemicalCurrent
        if experiment.silence {
            trace = NeuralTrace(input: input, chemical: chemicalCurrent, gap: gapCurrent)
            return
        }
        for edge in chemical {
            chemicalCurrent[edge.targetIndex] += parameters.chemicalGain * edge.polarity * edge.coefficient * state.activity[edge.sourceIndex]
        }
        var targets = Array(repeating: 0.0, count: count)
        var targetWeights = Array(repeating: 1.0, count: count)
        for i in 0..<count {
            let cell = cells[i]
            let drive = cell.bias + input.sensory[i] + input.proprioception[i]
                + cell.intrinsicGain * state.activity[i] - cell.adaptationGain * state.adaptation[i]
                + chemicalCurrent[i]
            targets[i] = tanh(drive)
        }
        for edge in gaps {
            let source = edge.sourceIndex
            let target = edge.targetIndex
            let conductance = parameters.gapGain * edge.coefficient
            let current = conductance * (state.activity[target] - state.activity[source])
            gapCurrent[source] += current
            gapCurrent[target] -= current
            // Incremental weighted convex averages evaluate the same target
            // without separately rounding its numerator and denominator. Each
            // bounded blend stays in [-1, 1], including saturated endpoints.
            targetWeights[source] += conductance
            targetWeights[target] += conductance
            let sourceFraction = conductance / targetWeights[source]
            let targetFraction = conductance / targetWeights[target]
            targets[source] = (1 - sourceFraction) * targets[source] + sourceFraction * state.activity[target]
            targets[target] = (1 - targetFraction) * targets[target] + targetFraction * state.activity[source]
        }
        var nextActivity = Array(repeating: 0.0, count: count)
        var nextAdaptation = nextActivity
        for i in 0..<count {
            let fraction = activityFraction[i]
            nextActivity[i] = (1 - fraction) * state.activity[i] + fraction * targets[i]
            let adaptation = adaptationFraction[i]
            nextAdaptation[i] = (1 - adaptation) * state.adaptation[i] + adaptation * state.activity[i]
        }
        state = NeuralState(activity: nextActivity, adaptation: nextAdaptation)
        trace = NeuralTrace(input: input, chemical: chemicalCurrent, gap: gapCurrent)
    }

    private static func validate(_ state: NeuralState, count: Int) throws {
        guard state.activity.count == count, state.adaptation.count == count,
              state.activity.allSatisfy({ $0.isFinite && (-1...1).contains($0) }),
              state.adaptation.allSatisfy({ $0.isFinite && (-1...1).contains($0) })
        else { throw NeuralError.invalidState }
    }
}
