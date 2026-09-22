/// All values here are MODEL assumptions, not measured electrophysiology.
public struct NeuralCellParameters: Equatable, Sendable {
    public var timeConstant: Double
    public var adaptationTimeConstant: Double
    public var intrinsicGain: Double
    public var adaptationGain: Double
    public var bias: Double

    public init(timeConstant: Double = 0.08, adaptationTimeConstant: Double = 0.6,
                intrinsicGain: Double = 0, adaptationGain: Double = 0.3, bias: Double = 0) {
        self.timeConstant = timeConstant
        self.adaptationTimeConstant = adaptationTimeConstant
        self.intrinsicGain = intrinsicGain
        self.adaptationGain = adaptationGain
        self.bias = bias
    }
}

public struct NeuralParameters: Equatable, Sendable {
    public static let version = "PetNeural.v1"
    public var chemicalGain: Double
    public var gapGain: Double
    public var ordinary: NeuralCellParameters
    public var smd: NeuralCellParameters
    public var initialSMDAmplitude: Double

    public init(chemicalGain: Double = 0.8, gapGain: Double = 0.15,
                ordinary: NeuralCellParameters = .init(),
                smd: NeuralCellParameters = .init(intrinsicGain: 2.2, adaptationGain: 2),
                initialSMDAmplitude: Double = 0.05) {
        self.chemicalGain = chemicalGain
        self.gapGain = gapGain
        self.ordinary = ordinary
        self.smd = smd
        self.initialSMDAmplitude = initialSMDAmplitude
    }

    public func cell(for id: String) -> NeuralCellParameters {
        Self.dorsalSMD.contains(id) || Self.ventralSMD.contains(id) ? smd : ordinary
    }

    public func initialState(neuronIDs: [String]) -> NeuralState {
        NeuralState(activity: neuronIDs.map {
            Self.dorsalSMD.contains($0) ? initialSMDAmplitude :
                (Self.ventralSMD.contains($0) ? -initialSMDAmplitude : 0)
        }, adaptation: Array(repeating: 0, count: neuronIDs.count))
    }

    /// Outgoing DD/VD and existing cross-dorsal/ventral SMD edges are inhibitory
    /// MODEL priors. This function can also label real NMJs in the motor model.
    public static func chemicalPolarity(source: String, target: String) -> Double {
        if inhibitorySources.contains(source) { return -1 }
        if (dorsalSMD.contains(source) && ventralSMD.contains(target)) ||
            (ventralSMD.contains(source) && dorsalSMD.contains(target)) { return -1 }
        return 1
    }

    private static let dorsalSMD: Set<String> = ["SMDDL", "SMDDR"]
    private static let ventralSMD: Set<String> = ["SMDVL", "SMDVR"]
    private static let inhibitorySources = Set((1...6).map { "DD\($0)" } + (1...13).map { "VD\($0)" })

    func validate() throws {
        for value in [chemicalGain, gapGain] {
            guard value.isFinite, (0...1_000_000).contains(value) else { throw NeuralError.invalidParameters }
        }
        for cell in [ordinary, smd] {
            guard cell.timeConstant.isFinite, cell.timeConstant > 0,
                  cell.adaptationTimeConstant.isFinite, cell.adaptationTimeConstant > 0,
                  [cell.intrinsicGain, cell.adaptationGain, cell.bias].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 })
            else { throw NeuralError.invalidParameters }
        }
        guard initialSMDAmplitude.isFinite, (0...1).contains(initialSMDAmplitude) else {
            throw NeuralError.invalidParameters
        }
    }
}

/// Immutable experiment configuration, never an environment command. Indices
/// address projection.graph.document.connections, including preserved diagonals.
public struct NeuralExperiment: Equatable, Sendable {
    public let disabledConnectionIndices: Set<Int>
    public let silence: Bool
    public init(disabledConnectionIndices: Set<Int> = [], silence: Bool = false) {
        self.disabledConnectionIndices = disabledConnectionIndices
        self.silence = silence
    }
}

public enum NeuralError: Error, Equatable, Sendable {
    case invalidParameters
    case invalidState
    case invalidInput
    case invalidConnectionIndex(Int)
}
