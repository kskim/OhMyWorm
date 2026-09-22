/// Immutable indexes over a validated document; no source values are rewritten.
/// Query lists retain the document's canonical (kind, source, target) order.
/// IDs are exact source IDs, not source-coordinate or dense runtime indices.
public struct ConnectomeGraph: Sendable {
    public let document: ConnectomeDocument
    public var neurons: [CellMetadata] { document.neurons }

    private let neuronIndices: [String: Int]
    private let incoming: [[Int]]
    private let outgoing: [[Int]]
    private let neighbors: [[Int]]
    private let electricalSelf: [[Int]]
    private let other: [String: [Int]]

    public init(document: ConnectomeDocument) {
        self.document = document
        let indices = Dictionary(uniqueKeysWithValues: document.neurons.enumerated().map { ($0.element.id, $0.offset) })
        neuronIndices = indices
        var incoming = Array(repeating: [Int](), count: document.neurons.count)
        var outgoing = incoming
        var neighbors = incoming
        var electricalSelf = incoming
        for (index, connection) in document.connections.enumerated() {
            // The document guarantees unique catalog IDs and neuronal endpoints.
            let source = indices[connection.source]!
            let target = indices[connection.target]!
            switch connection.kind {
            case .chemical:
                outgoing[source].append(index)
                incoming[target].append(index)
            case .gapJunction:
                if source == target {
                    electricalSelf[source].append(index)
                } else {
                    neighbors[source].append(index)
                    neighbors[target].append(index)
                }
            }
        }
        self.incoming = incoming
        self.outgoing = outgoing
        self.neighbors = neighbors
        self.electricalSelf = electricalSelf

        var other: [String: [Int]] = [:]
        for (index, connection) in document.otherConnections.enumerated() {
            other[connection.source, default: []].append(index)
            if connection.source != connection.target {
                other[connection.target, default: []].append(index)
            }
        }
        self.other = other
    }

    /// Missing IDs and other-cell IDs are not neurons.
    public func neuron(id: String) -> CellMetadata? {
        neuronIndices[id].map { document.neurons[$0] }
    }

    /// Neuron-only chemical inputs, including chemical self-records.
    public func chemicalIncoming(to id: String) -> [Connection] {
        guard let index = neuronIndices[id] else { return [] }
        return incoming[index].map { document.connections[$0] }
    }

    /// Neuron-only chemical outputs, including chemical self-records.
    public func chemicalOutgoing(from id: String) -> [Connection] {
        guard let index = neuronIndices[id] else { return [] }
        return outgoing[index].map { document.connections[$0] }
    }

    /// Off-diagonal neuronal gaps, accessible at either endpoint. Records retain
    /// canonical source/target orientation and both original source references.
    public func electricalNeighbors(of id: String) -> [Connection] {
        guard let index = neuronIndices[id] else { return [] }
        return neighbors[index].map { document.connections[$0] }
    }

    /// Diagonal electrical observations, never included in the neighbor list.
    public func electricalSelfObservations(for id: String) -> [Connection] {
        guard let index = neuronIndices[id] else { return [] }
        return electricalSelf[index].map { document.connections[$0] }
    }

    /// All incident records with an other-cell endpoint, including other-to-other
    /// and self-records (once). Accepts IDs from either cell partition.
    public func otherConnections(for id: String) -> [Connection] {
        other[id, default: []].map { document.otherConnections[$0] }
    }
}
