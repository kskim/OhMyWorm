import Foundation

enum RealBrainError: Error {
    case missingResource
    case unknownNeuron(String)
    case noMuscles
}

/// Loads the bundled real connectome exactly once per construction.
/// Local use only: redistribution rights for this dataset are unconfirmed,
/// so resolve data licensing before any public release.
enum RealDataLoader {
    static func loadGraph() throws -> ConnectomeGraph {
        guard let url = Bundle.main.url(forResource: "connectome", withExtension: "json") else {
            throw RealBrainError.missingResource
        }
        let data = try Data(contentsOf: url)
        return ConnectomeGraph(document: try ConnectomeDocument.decode(data))
    }
}

/// The full 302-neuron recurrent engine driving locomotion. Real anatomy
/// and real edges; everything below the REAL DATA line is a MODEL choice:
///
/// - Sensor mapping: food channels stimulate ASE/AWC taste neurons,
///   wall and cursor channels stimulate ALM/PLM touch neurons. Edge channels do NOT
///   touch the network (measured: they steer inward); edge preference is
///   an explicit tropism drive. Hunger scales sensory gains (0.6 + 0.8 *
///   hunger). CPG channels are dropped; the real network has its own
///   dynamics. Food stimulus adds a constant ventral offset (~-0.03 bend)
///   that steering overpowers.
/// - Steering is weathervane (klinotaxis): KlinotaxisController correlates
///   the ASE concentration derivative with head-swing velocity and writes
///   the bias into dorsal/ventral SMB+RMD head-motor neurons, plus explicit
///   food/edge/cursor drives (the touch path alone is too weak). Single-point
///   concentration only, like the real animal. SMD is excluded: its drive
///   inverts at mid-amplitude in this rate port (measured). ASE concentration
///   also inhibits B-class forward pools so the worm dwells near food.
/// - Readout: speed from B-class (forward) minus A-class (backward) motor
///   pools; turn from the muscle head-bend (anterior D/V minus body D/V),
///   with dorsal bends turning left (worm-on-side convention). The SMD
///   initial seed is zeroed: the port default (+0.05 dorsal) injects a
///   permanent dorsal veer into this readout (measured +0.18).
/// - Proprioception is zeros: the trail-body model has no neural feedback.
/// - 6 engine substeps (1/120 s each) per 1/20 s game tick.
struct RealBrain: LocomotionEngine {
    static let substeps = 6
    static let stimulusGain = 1.0
    static let turnGain = 2.0
    static let speedGain = 1.5

    private static let foodLeftIDs = ["ASEL", "AWCL"]
    private static let foodRightIDs = ["ASER", "AWCR"]
    private static let touchLeftIDs = ["ALML", "PLML"]
    private static let touchRightIDs = ["ALMR", "PLMR"]
    private static let tasteIDs = ["ASEL", "ASER", "AWCL", "AWCR"]
    private static let dorsalHeadIDs = ["SMBDL", "SMBDR", "RMDDL", "RMDDR"]
    private static let ventralHeadIDs = ["SMBVL", "SMBVR", "RMDVL", "RMDVR"]

    private var engine: NeuralEngine
    private(set) var muscles: MuscleLayer
    private(set) var klinotaxis = KlinotaxisController()
    private let klinoParams: KlinotaxisParameters
    private var pendingDrive = (dorsal: 0.0, ventral: 0.0)
    private var pendingDwell = 0.0
    private let count: Int
    private let foodLeft: [Int]
    private let foodRight: [Int]
    private let touchLeft: [Int]
    private let touchRight: [Int]
    private let taste: [Int]
    private let dorsalHead: [Int]
    private let ventralHead: [Int]
    private let forward: [Int]
    private let backward: [Int]

    init(graph: ConnectomeGraph, klinotaxis params: KlinotaxisParameters = .init()) throws {
        let projection = NeuralProjection(graph: graph)
        var neuralParams = NeuralParameters()
        neuralParams.initialSMDAmplitude = 0
        engine = try NeuralEngine(projection: projection, parameters: neuralParams)
        klinoParams = params
        count = projection.neuronIDs.count
        func resolve(_ id: String) throws -> Int {
            guard let index = projection.index(of: id) else {
                throw RealBrainError.unknownNeuron(id)
            }
            return index
        }
        foodLeft = try Self.foodLeftIDs.map(resolve)
        foodRight = try Self.foodRightIDs.map(resolve)
        touchLeft = try Self.touchLeftIDs.map(resolve)
        touchRight = try Self.touchRightIDs.map(resolve)
        taste = try Self.tasteIDs.map(resolve)
        dorsalHead = try Self.dorsalHeadIDs.map(resolve)
        ventralHead = try Self.ventralHeadIDs.map(resolve)
        var forward: [Int] = []
        var backward: [Int] = []
        for (index, meta) in graph.neurons.enumerated() {
            guard meta.sourceRoles.contains("motor") else { continue }
            if meta.id.hasPrefix("DB") || meta.id.hasPrefix("VB") {
                forward.append(index)
            } else if meta.id.hasPrefix("DA") || meta.id.hasPrefix("VA") {
                backward.append(index)
            }
        }
        self.forward = forward
        self.backward = backward
        muscles = try MuscleLayer(graph: graph, neuronIndex: projection.index(of:))
    }

    mutating func step(_ inputs: [Double]) -> (turn: Double, speed: Double) {
        precondition(inputs.count == MiniBrain.Sensor.count)
        var sensory = [Double](repeating: 0, count: count)
        let hungerGain = 0.6 + 0.8 * inputs[MiniBrain.Sensor.hunger.rawValue]
        func stimulate(_ indices: [Int], _ value: Double) {
            for index in indices {
                sensory[index] += value * hungerGain * Self.stimulusGain
            }
        }
        let foodProximity = inputs[MiniBrain.Sensor.foodProximity.rawValue]
        stimulate(foodLeft, inputs[MiniBrain.Sensor.foodLeft.rawValue] + 0.5 * foodProximity)
        stimulate(foodRight, inputs[MiniBrain.Sensor.foodRight.rawValue] + 0.5 * foodProximity)
        // Touch: wall and cursor. Wall stimulus avoids correctly through the D/V
        // readout (measured +/-0.03); edge stimulus steers inward (measured),
        // so edge preference is an explicit tropism drive, not touch.
        stimulate(touchLeft, inputs[MiniBrain.Sensor.wallLeft.rawValue])
        stimulate(touchRight, inputs[MiniBrain.Sensor.wallRight.rawValue])
        stimulate(touchLeft, inputs[MiniBrain.Sensor.cursorLeft.rawValue])
        stimulate(touchRight, inputs[MiniBrain.Sensor.cursorRight.rawValue])
        // Motor write: bypasses hunger-scaled stimulate(); this is a
        // steering command, not a sensory gain.
        for index in dorsalHead { sensory[index] += pendingDrive.dorsal }
        for index in ventralHead { sensory[index] += pendingDrive.ventral }
        for index in forward { sensory[index] += pendingDwell }
        let input = NeuralInput(sensory: sensory, proprioception: [Double](repeating: 0, count: count))
        // Step validates before mutating, and sizes match by construction,
        // so a throw here is unreachable; try? keeps the non-throwing seam.
        for _ in 0..<Self.substeps { try? engine.step(input: input) }
        let activity = engine.state.activity
        let concentration = mean(activity, taste)
        let lateral = inputs[MiniBrain.Sensor.foodLeft.rawValue] - inputs[MiniBrain.Sensor.foodRight.rawValue]
        let edgeLateral = inputs[MiniBrain.Sensor.edgeLeft.rawValue] - inputs[MiniBrain.Sensor.edgeRight.rawValue]
        let threatLateral = inputs[MiniBrain.Sensor.cursorLeft.rawValue] - inputs[MiniBrain.Sensor.cursorRight.rawValue]
        pendingDrive = klinotaxis.step(concentration: concentration, proximity: foodProximity,
                                       lateral: lateral, edgeLateral: edgeLateral,
                                       threatLateral: threatLateral, params: klinoParams)
        pendingDwell = -min(klinoParams.dwellGain * concentration, klinoParams.dwellCap)
        muscles.step(activity: activity)
        return (
            Self.readoutTurn(bend: muscles.headBend),
            Self.readoutSpeed(forward: mean(activity, forward), backward: mean(activity, backward))
        )
    }

    static func readoutTurn(bend: Double) -> Double {
        min(max(bend * turnGain, -1), 1)
    }

    static func readoutSpeed(forward: Double, backward: Double) -> Double {
        min(max(0.5 + (forward - backward) * speedGain, 0), 1)
    }

    private func mean(_ activity: [Double], _ indices: [Int]) -> Double {
        guard !indices.isEmpty else { return 0 }
        return indices.reduce(0) { $0 + activity[$1] } / Double(indices.count)
    }
}
