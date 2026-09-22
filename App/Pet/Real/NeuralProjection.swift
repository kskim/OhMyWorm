import Foundation

/// Immutable real anatomy plus a separate, canonically ordered MODEL projection.
/// Chemical self-records remain active; gap diagonals remain raw records only.
public struct NeuralProjection: Sendable {
    public struct Edge: Equatable, Sendable {
        public let connectionIndex: Int
        public let sourceIndex: Int
        public let targetIndex: Int
        public let coefficient: Double
        public let polarity: Double
    }
    public let graph: ConnectomeGraph
    public let neuronIDs: [String]
    public let chemical: [Edge]
    public let gaps: [Edge]
    private let indices: [String: Int]

    public init(graph: ConnectomeGraph) {
        self.graph = graph
        neuronIDs = graph.neurons.map(\.id)
        let indices = Dictionary(uniqueKeysWithValues: neuronIDs.enumerated().map { ($0.element, $0.offset) })
        self.indices = indices
        var incoming = Array(repeating: 0.0, count: neuronIDs.count)
        var degree = incoming
        for record in graph.document.connections {
            let source = indices[record.source]!
            let target = indices[record.target]!
            let weight = sqrt(Double(record.rawWeight))
            if record.kind == .chemical {
                incoming[target] += weight
            } else if source != target {
                degree[source] += weight
                degree[target] += weight
            }
        }
        let maximumDegree = max(1, degree.max() ?? 0)
        var chemical: [Edge] = []
        var gaps: [Edge] = []
        for (index, record) in graph.document.connections.enumerated() {
            let source = indices[record.source]!
            let target = indices[record.target]!
            let weight = sqrt(Double(record.rawWeight))
            if record.kind == .chemical {
                chemical.append(Edge(connectionIndex: index, sourceIndex: source, targetIndex: target,
                                     coefficient: weight / max(1, incoming[target]),
                                     polarity: NeuralParameters.chemicalPolarity(source: record.source, target: record.target)))
            } else if source != target {
                gaps.append(Edge(connectionIndex: index, sourceIndex: source, targetIndex: target,
                                 coefficient: weight / maximumDegree, polarity: 1))
            }
        }
        self.chemical = chemical
        self.gaps = gaps
    }

    public func index(of neuronID: String) -> Int? { indices[neuronID] }
}
