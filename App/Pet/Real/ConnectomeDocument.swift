import Foundation

public enum ConnectomeDocumentError: Error, Equatable, Sendable {
    case malformedJSON
    case requiresValidatedDecode
    case invalidStructure(path: String)
    case unsupportedSchemaVersion(Int)
    case unsupportedNormalizationVersion(Int)
    case invalidField(String)
    case invalidWeight(source: String, target: String)
    case invalidMetadata(String)
    case invalidReference(String)
    case duplicateID(String)
    case duplicateConnection(kind: String, source: String, target: String)
    case danglingEndpoint(String)
    case invalidPartition(source: String, target: String)
    case invalidGapOrdering(source: String, target: String)
    case nonCanonicalOrder(String)
    case inconsistentCoordinates
}

// Only the byte boundary can inspect exact number spelling. Ordinary Decoder
// implementations have already lost it (Foundation can round fractions to Int).
private let exactInputKey = CodingUserInfoKey(rawValue: "WormCore.exactRuntimeInput")!
private struct ExactRuntimeInput: Sendable {}
private func requireExactInput(_ decoder: any Decoder) throws {
    guard decoder.userInfo[exactInputKey] is ExactRuntimeInput else {
        throw ConnectomeDocumentError.requiresValidatedDecode
    }
}

private func requireText(_ text: String, _ field: String) throws {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw ConnectomeDocumentError.invalidField(field)
    }
}

private func requireHash(_ hash: String, _ field: String) throws {
    guard hash.utf8.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
        throw ConnectomeDocumentError.invalidField(field)
    }
}

private func requireURL(_ text: String, _ field: String) throws {
    guard let url = URL(string: text), url.scheme == "https", let host = url.host, !host.isEmpty else {
        throw ConnectomeDocumentError.invalidField(field)
    }
}

public struct ConnectomeDataset: Codable, Equatable, Sendable {
    public let id: String
    public let organism: String
    public let stage: String
    public let sex: String
    public let citation: String
    public let doi: String
    public let sourceRevision: String
    public let weightUnit: String

    public init(id: String, organism: String, stage: String, sex: String, citation: String,
                doi: String, sourceRevision: String, weightUnit: String = "emSectionCount") throws {
        for (field, value) in [("id", id), ("organism", organism), ("stage", stage), ("sex", sex),
                               ("citation", citation), ("sourceRevision", sourceRevision)] {
            try requireText(value, "dataset.\(field)")
        }
        try requireURL(doi, "dataset.doi")
        guard weightUnit == "emSectionCount" else { throw ConnectomeDocumentError.invalidField("dataset.weightUnit") }
        self.id = id; self.organism = organism; self.stage = stage; self.sex = sex
        self.citation = citation; self.doi = doi; self.sourceRevision = sourceRevision; self.weightUnit = weightUnit
    }

    private enum CodingKeys: String, CodingKey { case id, organism, stage, sex, citation, doi, sourceRevision, weightUnit }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(String.self, forKey: .id), organism: c.decode(String.self, forKey: .organism),
                      stage: c.decode(String.self, forKey: .stage), sex: c.decode(String.self, forKey: .sex),
                      citation: c.decode(String.self, forKey: .citation), doi: c.decode(String.self, forKey: .doi),
                      sourceRevision: c.decode(String.self, forKey: .sourceRevision), weightUnit: c.decode(String.self, forKey: .weightUnit))
    }
}

public struct SourceArtifact: Codable, Equatable, Sendable {
    public let url: String
    public let sha256: String

    public init(url: String, sha256: String) throws {
        try requireURL(url, "source.url"); try requireHash(sha256, "source.sha256")
        self.url = url; self.sha256 = sha256
    }

    private enum CodingKeys: String, CodingKey { case url, sha256 }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(url: c.decode(String.self, forKey: .url), sha256: c.decode(String.self, forKey: .sha256))
    }
}

public struct ConnectomeProvenance: Codable, Equatable, Sendable {
    public let cache: SourceArtifact
    public let catalog: SourceArtifact
    public let metadataSHA256: String
    public let upstreamWorkbook: String
    public let normalizationVersion: Int
    public let redistributionStatus: String
    public let workbookEquivalence: String

    public init(cache: SourceArtifact, catalog: SourceArtifact, metadataSHA256: String, upstreamWorkbook: String,
                normalizationVersion: Int = 1, redistributionStatus: String = "unconfirmed",
                workbookEquivalence: String = "unverified") throws {
        guard normalizationVersion == 1 else { throw ConnectomeDocumentError.unsupportedNormalizationVersion(normalizationVersion) }
        try requireHash(metadataSHA256, "provenance.metadataSHA256")
        try requireURL(upstreamWorkbook, "provenance.upstreamWorkbook")
        guard redistributionStatus == "unconfirmed" else { throw ConnectomeDocumentError.invalidField("provenance.redistributionStatus") }
        guard workbookEquivalence == "unverified" else { throw ConnectomeDocumentError.invalidField("provenance.workbookEquivalence") }
        self.cache = cache; self.catalog = catalog; self.metadataSHA256 = metadataSHA256
        self.upstreamWorkbook = upstreamWorkbook; self.normalizationVersion = normalizationVersion
        self.redistributionStatus = redistributionStatus; self.workbookEquivalence = workbookEquivalence
    }

    private enum CodingKeys: String, CodingKey {
        case cache, catalog, metadataSHA256, upstreamWorkbook, normalizationVersion, redistributionStatus, workbookEquivalence
    }
    public init(from decoder: any Decoder) throws {
        try requireExactInput(decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(cache: c.decode(SourceArtifact.self, forKey: .cache), catalog: c.decode(SourceArtifact.self, forKey: .catalog),
                      metadataSHA256: c.decode(String.self, forKey: .metadataSHA256), upstreamWorkbook: c.decode(String.self, forKey: .upstreamWorkbook),
                      normalizationVersion: c.decode(Int.self, forKey: .normalizationVersion),
                      redistributionStatus: c.decode(String.self, forKey: .redistributionStatus),
                      workbookEquivalence: c.decode(String.self, forKey: .workbookEquivalence))
    }
}

public struct CellAnatomy: Codable, Equatable, Sendable {
    public let system: String?

    public init(system: String?) throws {
        guard system == nil || system == "pharyngeal" || system == "nonpharyngeal" else {
            throw ConnectomeDocumentError.invalidField("anatomy.system")
        }
        self.system = system
    }

    private enum CodingKeys: String, CodingKey { case system }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(system: c.decode(String?.self, forKey: .system))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(system, forKey: .system)
    }
}

/// Catalog references retain task3's field/hash/symbol shape. Cache node
/// references instead carry nodeIndex, for other-cell id and name fields.
public struct CellSourceReference: Codable, Equatable, Sendable {
    public let field: String
    public let sha256: String
    public let symbol: String?
    public let nodeIndex: Int?

    public init(field: String, sha256: String, symbol: String? = nil, nodeIndex: Int? = nil) throws {
        try requireHash(sha256, "cellReference.sha256")
        guard ["id", "name", "sourceRoles", "anatomy.system"].contains(field),
              (symbol != nil) != (nodeIndex != nil), nodeIndex.map({ $0 >= 0 }) ?? true else {
            throw ConnectomeDocumentError.invalidReference(field)
        }
        if let symbol { try requireText(symbol, "cellReference.symbol") }
        self.field = field; self.sha256 = sha256; self.symbol = symbol; self.nodeIndex = nodeIndex
    }

    private enum CodingKeys: String, CodingKey { case field, sha256, symbol, nodeIndex }
    public init(from decoder: any Decoder) throws {
        try requireExactInput(decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(field: c.decode(String.self, forKey: .field), sha256: c.decode(String.self, forKey: .sha256),
                      symbol: c.decodeIfPresent(String.self, forKey: .symbol), nodeIndex: c.decodeIfPresent(Int.self, forKey: .nodeIndex))
    }
}

public struct CellMetadata: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let sourceRoles: [String]
    public let neuronClass: String?
    public let anatomy: CellAnatomy?
    public let sourceReferences: [CellSourceReference]

    fileprivate static let roleSymbols = ["sensory": "SENSORY_NEURONS_COOK", "interneuron": "INTERNEURONS_COOK",
                                          "motor": "MOTORNEURONS_COOK", "polymodal": "PHARYNGEAL_POLYMODAL_NEURONS",
                                          "unknown": "UNKNOWN_FUNCTION_NEURONS"]

    public init(id: String, name: String, aliases: [String] = [], sourceRoles: [String], neuronClass: String? = nil,
                anatomy: CellAnatomy?, sourceReferences: [CellSourceReference]) throws {
        guard !id.isEmpty, id == id.trimmingCharacters(in: .whitespacesAndNewlines), name == id,
              aliases.isEmpty, neuronClass == nil,
              sourceRoles == Array(Set(sourceRoles)).sorted(), sourceRoles.allSatisfy({ Self.roleSymbols[$0] != nil }) else {
            throw ConnectomeDocumentError.invalidMetadata(id)
        }
        let expectedSymbols = ["id": "PREFERRED_HERM_NEURON_NAMES", "name": "PREFERRED_HERM_NEURON_NAMES",
                               "anatomy.system": "PHARYNGEAL_NEURONS"]
        var seen = Set<String>()
        var previous = ""
        for reference in sourceReferences {
            let key = reference.field + ":" + (reference.symbol ?? "")
            guard seen.insert(key).inserted, previous < key else { throw ConnectomeDocumentError.invalidReference(id) }
            previous = key
            if let symbol = reference.symbol {
                let valid = reference.field == "sourceRoles" ? sourceRoles.contains(where: { Self.roleSymbols[$0] == symbol })
                    : expectedSymbols[reference.field] == symbol
                guard valid else { throw ConnectomeDocumentError.invalidReference(id) }
            } else {
                guard reference.field == "id" || reference.field == "name" else { throw ConnectomeDocumentError.invalidReference(id) }
            }
        }
        let fields = sourceReferences.map(\.field)
        guard fields.filter({ $0 == "id" }).count == 1, fields.filter({ $0 == "name" }).count == 1,
              fields.filter({ $0 == "sourceRoles" }).count == sourceRoles.count,
              fields.filter({ $0 == "anatomy.system" }).count == (anatomy?.system == nil ? 0 : 1) else {
            throw ConnectomeDocumentError.invalidReference(id)
        }
        self.id = id; self.name = name; self.aliases = aliases; self.sourceRoles = sourceRoles
        self.neuronClass = neuronClass; self.anatomy = anatomy; self.sourceReferences = sourceReferences
    }

    private enum CodingKeys: String, CodingKey { case id, name, aliases, sourceRoles, neuronClass, anatomy, sourceReferences }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: c.decode(String.self, forKey: .id), name: c.decode(String.self, forKey: .name),
                      aliases: c.decode([String].self, forKey: .aliases), sourceRoles: c.decode([String].self, forKey: .sourceRoles),
                      neuronClass: c.decode(String?.self, forKey: .neuronClass), anatomy: c.decode(CellAnatomy?.self, forKey: .anatomy),
                      sourceReferences: c.decode([CellSourceReference].self, forKey: .sourceReferences))
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name); try c.encode(aliases, forKey: .aliases)
        try c.encode(sourceRoles, forKey: .sourceRoles); try c.encode(neuronClass, forKey: .neuronClass)
        try c.encode(anatomy, forKey: .anatomy); try c.encode(sourceReferences, forKey: .sourceReferences)
    }
}

public struct ConnectionSourceReference: Codable, Equatable, Sendable {
    public let sha256: String
    public let matrix: String
    public let row: Int
    public let column: Int

    public init(sha256: String, matrix: String, row: Int, column: Int) throws {
        try requireHash(sha256, "connectionReference.sha256")
        guard ["Generic_CS", "Generic_GJ"].contains(matrix), row >= 0, column >= 0 else {
            throw ConnectomeDocumentError.invalidReference(matrix)
        }
        self.sha256 = sha256; self.matrix = matrix; self.row = row; self.column = column
    }

    private enum CodingKeys: String, CodingKey { case sha256, matrix, row, column }
    public init(from decoder: any Decoder) throws {
        try requireExactInput(decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sha256: c.decode(String.self, forKey: .sha256), matrix: c.decode(String.self, forKey: .matrix),
                      row: c.decode(Int.self, forKey: .row), column: c.decode(Int.self, forKey: .column))
    }
}

public struct Connection: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case chemical, gapJunction }
    public let kind: Kind
    public let source: String
    public let target: String
    public let rawWeight: Int
    public let weightUnit: String
    public let sourceReferences: [ConnectionSourceReference]

    public init(kind: Kind, source: String, target: String, rawWeight: Int, weightUnit: String = "emSectionCount",
                sourceReferences: [ConnectionSourceReference]) throws {
        try requireText(source, "connection.source"); try requireText(target, "connection.target")
        guard rawWeight > 0 else { throw ConnectomeDocumentError.invalidWeight(source: source, target: target) }
        guard weightUnit == "emSectionCount" else { throw ConnectomeDocumentError.invalidField("connection.weightUnit") }
        guard kind != .gapJunction || source <= target else {
            throw ConnectomeDocumentError.invalidGapOrdering(source: source, target: target)
        }
        let matrix = kind == .chemical ? "Generic_CS" : "Generic_GJ"
        let count = kind == .gapJunction && source != target ? 2 : 1
        guard sourceReferences.count == count, sourceReferences.allSatisfy({ $0.matrix == matrix }),
              let first = sourceReferences.first,
              (source == target) == (first.row == first.column) else {
            throw ConnectomeDocumentError.invalidReference("\(source)->\(target)")
        }
        if count == 2 {
            let second = sourceReferences[1]
            guard first.row < first.column, first.row == second.column, first.column == second.row,
                  first.sha256 == second.sha256 else {
                throw ConnectomeDocumentError.invalidReference("\(source)->\(target)")
            }
        }
        self.kind = kind; self.source = source; self.target = target; self.rawWeight = rawWeight
        self.weightUnit = weightUnit; self.sourceReferences = sourceReferences
    }

    private enum CodingKeys: String, CodingKey { case kind, source, target, rawWeight, weightUnit, sourceReferences }
    public init(from decoder: any Decoder) throws {
        try requireExactInput(decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let source = try c.decode(String.self, forKey: .source)
        let target = try c.decode(String.self, forKey: .target)
        let weight: Int
        do { weight = try c.decode(Int.self, forKey: .rawWeight) }
        catch { throw ConnectomeDocumentError.invalidWeight(source: source, target: target) }
        try self.init(kind: c.decode(Kind.self, forKey: .kind), source: source, target: target, rawWeight: weight,
                      weightUnit: c.decode(String.self, forKey: .weightUnit),
                      sourceReferences: c.decode([ConnectionSourceReference].self, forKey: .sourceReferences))
    }
}

/// Immutable schema v1. Construct with checked values, or decode JSON bytes using
/// `decode(_:)` (not JSONDecoder directly). Source-specific pins/cardinality and
/// source-to-document equivalence are the importer's responsibility.
public struct ConnectomeDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let dataset: ConnectomeDataset
    public let provenance: ConnectomeProvenance
    public let neurons: [CellMetadata]
    public let otherCells: [CellMetadata]
    public let connections: [Connection]
    public let otherConnections: [Connection]

    public init(schemaVersion: Int = 1, dataset: ConnectomeDataset, provenance: ConnectomeProvenance,
                neurons: [CellMetadata], otherCells: [CellMetadata], connections: [Connection], otherConnections: [Connection]) throws {
        guard schemaVersion == 1 else { throw ConnectomeDocumentError.unsupportedSchemaVersion(schemaVersion) }
        self.schemaVersion = schemaVersion; self.dataset = dataset; self.provenance = provenance
        self.neurons = neurons; self.otherCells = otherCells; self.connections = connections; self.otherConnections = otherConnections
        try validateReferencesAndPartitions()
    }

    public static func decode(_ data: Data) throws -> ConnectomeDocument {
        do {
            let decoder = JSONDecoder()
            _ = try decoder.decode(JSONSyntax.self, from: data)
            let exactData = try ExactNumbers.prepare(data, invalidNumber: "{}")
            decoder.userInfo[exactInputKey] = ExactRuntimeInput()
            return try decoder.decode(Self.self, from: exactData)
        } catch RawConnectomeError.malformedJSON {
            throw ConnectomeDocumentError.malformedJSON
        } catch DecodingError.dataCorrupted(let context) {
            if context.codingPath.isEmpty { throw ConnectomeDocumentError.malformedJSON }
            throw ConnectomeDocumentError.invalidStructure(path: Self.path(context.codingPath))
        } catch DecodingError.keyNotFound(let key, let context) {
            throw ConnectomeDocumentError.invalidStructure(path: Self.path(context.codingPath + [key]))
        } catch DecodingError.typeMismatch(_, let context) {
            throw ConnectomeDocumentError.invalidStructure(path: Self.path(context.codingPath))
        } catch DecodingError.valueNotFound(_, let context) {
            throw ConnectomeDocumentError.invalidStructure(path: Self.path(context.codingPath))
        }
    }

    /// Canonical UTF-8 JSON, sorted object keys, stable indentation and newline.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(10)
        return data
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, dataset, provenance, neurons, otherCells, connections, otherConnections }
    public init(from decoder: any Decoder) throws {
        try requireExactInput(decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 else { throw ConnectomeDocumentError.unsupportedSchemaVersion(version) }
        try self.init(schemaVersion: version, dataset: c.decode(ConnectomeDataset.self, forKey: .dataset),
                      provenance: c.decode(ConnectomeProvenance.self, forKey: .provenance),
                      neurons: c.decode([CellMetadata].self, forKey: .neurons), otherCells: c.decode([CellMetadata].self, forKey: .otherCells),
                      connections: c.decode([Connection].self, forKey: .connections), otherConnections: c.decode([Connection].self, forKey: .otherConnections))
    }

    private static func path(_ keys: [any CodingKey]) -> String {
        keys.isEmpty ? "$" : keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }

    private func validateReferencesAndPartitions() throws {
        let cells = neurons + otherCells
        var ids = Set<String>()
        for cell in cells {
            guard ids.insert(cell.id).inserted else { throw ConnectomeDocumentError.duplicateID(cell.id) }
        }
        for (name, partition) in [("neurons", neurons), ("otherCells", otherCells)] {
            guard partition.map(\.id) == partition.map(\.id).sorted() else { throw ConnectomeDocumentError.nonCanonicalOrder(name) }
        }
        let neuronIDs = Set(neurons.map(\.id))
        // Candidate cache indices, not a persisted graph/query index. Catalog
        // metadata has no cache index. A mirrored gap constrains BOTH endpoints
        // to its two coordinates; sorting IDs does not sort source node indices.
        var candidates: [String: Set<Int>] = [:]
        func constrain(_ id: String, to indices: Set<Int>) throws {
            guard indices.allSatisfy({ $0 >= 0 && $0 < cells.count }) else { throw ConnectomeDocumentError.inconsistentCoordinates }
            let remaining = candidates[id].map { $0.intersection(indices) } ?? indices
            guard !remaining.isEmpty else { throw ConnectomeDocumentError.inconsistentCoordinates }
            candidates[id] = remaining
        }
        for cell in cells {
            let isNeuron = neuronIDs.contains(cell.id)
            guard isNeuron ? !cell.sourceRoles.isEmpty : (cell.sourceRoles.isEmpty && cell.anatomy == nil) else {
                throw ConnectomeDocumentError.invalidMetadata(cell.id)
            }
            for reference in cell.sourceReferences {
                if isNeuron {
                    guard reference.symbol != nil, reference.nodeIndex == nil, reference.sha256 == provenance.catalog.sha256 else {
                        throw ConnectomeDocumentError.invalidReference(cell.id)
                    }
                } else {
                    guard reference.symbol == nil, let index = reference.nodeIndex, reference.sha256 == provenance.cache.sha256 else {
                        throw ConnectomeDocumentError.invalidReference(cell.id)
                    }
                    try constrain(cell.id, to: [index])
                }
            }
        }
        var keys = Set<[String]>()
        for (name, partition) in [("connections", connections), ("otherConnections", otherConnections)] {
            var previous: [String]?
            for connection in partition {
                let key = [connection.kind.rawValue, connection.source, connection.target]
                guard keys.insert(key).inserted else {
                    throw ConnectomeDocumentError.duplicateConnection(kind: key[0], source: key[1], target: key[2])
                }
                if let previous, !previous.lexicographicallyPrecedes(key) { throw ConnectomeDocumentError.nonCanonicalOrder(name) }
                previous = key
                for endpoint in [connection.source, connection.target] where !ids.contains(endpoint) {
                    throw ConnectomeDocumentError.danglingEndpoint(endpoint)
                }
                let neuronal = neuronIDs.contains(connection.source) && neuronIDs.contains(connection.target)
                guard neuronal == (name == "connections") else {
                    throw ConnectomeDocumentError.invalidPartition(source: connection.source, target: connection.target)
                }
                for reference in connection.sourceReferences where reference.sha256 != provenance.cache.sha256 {
                    throw ConnectomeDocumentError.invalidReference("\(connection.source)->\(connection.target)")
                }
                let reference = connection.sourceReferences[0] // Checked nonempty by Connection.
                if connection.kind == .chemical || connection.source == connection.target {
                    try constrain(connection.source, to: [reference.row])
                    try constrain(connection.target, to: [reference.column])
                } else {
                    let pair: Set<Int> = [reference.row, reference.column]
                    try constrain(connection.source, to: pair)
                    try constrain(connection.target, to: pair)
                }
            }
        }
        // Require an injective cell->cache-index assignment. Each gap's two
        // distinct endpoints then occupy exactly its two mirrored coordinates.
        // Isolated neurons need no invented index: unused indices remain free.
        var owner: [Int: String] = [:]
        func assign(_ id: String, visited: inout Set<Int>) -> Bool {
            for index in candidates[id, default: []].sorted() where visited.insert(index).inserted {
                if let occupant = owner[index], !assign(occupant, visited: &visited) { continue }
                owner[index] = id
                return true
            }
            return false
        }
        for id in candidates.keys.sorted() {
            var visited = Set<Int>()
            guard assign(id, visited: &visited) else { throw ConnectomeDocumentError.inconsistentCoordinates }
        }
    }
}
