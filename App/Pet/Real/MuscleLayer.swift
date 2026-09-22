import Foundation

/// Body-wall muscles driven by real neuromuscular junctions (NMJ).
/// REAL DATA: 95 M[DV][LR] muscles, chemical + neuron-muscle gap NMJ edges
/// from the bundled connectome, DD/VD inhibitory polarity. D/V innervation
/// is ~ipsilateral (dorsal motor -> dorsal muscle); L/R is crossed, so the
/// bend readout uses the D/V axis, not L/R.
/// MODEL: leaky tanh activation per muscle (updateRate toward tanh(drive));
/// muscle-to-muscle gap coupling is skipped. `headBend` reads the anterior
/// D/V differential minus the body D/V differential (head lead over posture).
struct MuscleLayer: Sendable {
    struct Edge: Sendable {
        let neuronIndex: Int
        let muscleIndex: Int
        let coefficient: Double
        let polarity: Double
    }

    static let updateRate = 0.35
    static let driveGain = 1.0
    /// RMD/RME NMJs stay within 01-08; that is the steering head.
    static let anteriorMax = 8

    let muscleIDs: [String]
    let anteriorDorsal: [Int]
    let anteriorVentral: [Int]
    let bodyDorsal: [Int]
    let bodyVentral: [Int]
    let edges: [Edge]
    private(set) var activation: [Double]

    init(graph: ConnectomeGraph, neuronIndex: (String) -> Int?) throws {
        let muscles = graph.document.otherCells.map(\.id).filter(Self.isBodyWallMuscle).sorted()
        guard !muscles.isEmpty else { throw RealBrainError.noMuscles }
        let muscleIndex = Dictionary(uniqueKeysWithValues: muscles.enumerated().map { ($0.element, $0.offset) })
        var raw: [(neuron: String, muscle: Int, weight: Double, polarity: Double)] = []
        for connection in graph.document.otherConnections {
            guard connection.source != connection.target else { continue }
            let weight = sqrt(Double(connection.rawWeight))
            switch connection.kind {
            case .chemical:
                // Validated data orients these neuron -> muscle; still verify.
                if neuronIndex(connection.source) != nil, let muscle = muscleIndex[connection.target] {
                    raw.append((connection.source, muscle, weight,
                                NeuralParameters.chemicalPolarity(source: connection.source, target: connection.target)))
                }
            case .gapJunction:
                // Canonical order, not direction: find the neuron endpoint.
                if neuronIndex(connection.source) != nil, let muscle = muscleIndex[connection.target] {
                    raw.append((connection.source, muscle, weight, 1))
                } else if neuronIndex(connection.target) != nil, let muscle = muscleIndex[connection.source] {
                    raw.append((connection.target, muscle, weight, 1))
                }
            }
        }
        var incoming = Array(repeating: 0.0, count: muscles.count)
        for edge in raw { incoming[edge.muscle] += edge.weight }
        edges = raw.map {
            Edge(neuronIndex: neuronIndex($0.neuron)!, muscleIndex: $0.muscle,
                 coefficient: $0.weight / max(1, incoming[$0.muscle]), polarity: $0.polarity)
        }
        muscleIDs = muscles
        func pool(dorsal: Bool, anterior: Bool) -> [Int] {
            muscles.indices.filter {
                let id = muscles[$0]
                let isDorsal = id.dropFirst().first == "D"
                let isAnterior = Self.bodyNumber(id) <= Self.anteriorMax
                return isDorsal == dorsal && isAnterior == anterior
            }
        }
        anteriorDorsal = pool(dorsal: true, anterior: true)
        anteriorVentral = pool(dorsal: false, anterior: true)
        bodyDorsal = pool(dorsal: true, anterior: false)
        bodyVentral = pool(dorsal: false, anterior: false)
        activation = Array(repeating: 0, count: muscles.count)
    }

    static func bodyNumber(_ id: String) -> Int {
        Int(id.dropFirst(3)) ?? Int.max
    }

    static func isBodyWallMuscle(_ id: String) -> Bool {
        // M + dorsal/ventral + left/right + body position, e.g. MDL03.
        guard id.count >= 4, id.first == "M" else { return false }
        let chars = Array(id)
        guard chars[1] == "D" || chars[1] == "V", chars[2] == "L" || chars[2] == "R" else { return false }
        return chars[3...].allSatisfy(\.isNumber)
    }

    mutating func step(activity: [Double]) {
        var drive = Array(repeating: 0.0, count: muscleIDs.count)
        for edge in edges {
            drive[edge.muscleIndex] += edge.polarity * edge.coefficient * activity[edge.neuronIndex]
        }
        for index in activation.indices {
            activation[index] += Self.updateRate * (tanh(Self.driveGain * drive[index]) - activation[index])
        }
    }

    /// Head D/V bend minus body D/V bend. Positive bends dorsal.
    var headBend: Double {
        (mean(activation, anteriorDorsal) - mean(activation, anteriorVentral))
            - (mean(activation, bodyDorsal) - mean(activation, bodyVentral))
    }

    private func mean(_ values: [Double], _ indices: [Int]) -> Double {
        guard !indices.isEmpty else { return 0 }
        return indices.reduce(0) { $0 + values[$1] } / Double(indices.count)
    }
}
