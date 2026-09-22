import Foundation

public enum RawConnectomeError: Error, Equatable, Sendable {
    case malformedJSON
    case invalidStructure(path: String)
    case emptyID(index: Int)
    case duplicateID(String)
    case missingMatrix(String)
    case unsupportedMatrix(String)
    case rowCount(matrix: String, expected: Int, actual: Int)
    case columnCount(matrix: String, row: Int, expected: Int, actual: Int)
    case invalidWeight(matrix: String, row: Int, column: Int)
    case asymmetricGap(row: Int, column: Int)
}

/// Validated source matrices, without normalization or catalog assumptions.
/// Rows are sources and columns are targets in `nodes` order. Zero cells,
/// diagonals and isolated nodes are retained; summary text is not decoded.
public struct RawConnectome: Sendable {
    public let nodes: [String]
    public let chemical: [[Int]]
    public let gapJunction: [[Int]]

    private init(source: Source) {
        nodes = source.nodes
        chemical = source.chemical
        gapJunction = source.gapJunction
    }

    /// Weights must be nonnegative integers representable by Swift `Int`.
    /// JSON decimal/exponent notation is accepted when its value is integral.
    public static func decode(_ data: Data) throws -> RawConnectome {
        do {
            let decoder = JSONDecoder()
            // Parse structure before touching numeric spelling; ExactNumbers
            // rejects permissive syntax without converting overflowing numbers.
            _ = try decoder.decode(JSONSyntax.self, from: data)
            let exactData = try ExactNumbers.prepare(data)
            return RawConnectome(source: try decoder.decode(Source.self, from: exactData))
        } catch DecodingError.dataCorrupted {
            throw RawConnectomeError.malformedJSON
        } catch DecodingError.keyNotFound(let key, let context) {
            throw RawConnectomeError.invalidStructure(path: path(context.codingPath + [key]))
        } catch DecodingError.typeMismatch(_, let context) {
            throw RawConnectomeError.invalidStructure(path: path(context.codingPath))
        } catch DecodingError.valueNotFound(_, let context) {
            throw RawConnectomeError.invalidStructure(path: path(context.codingPath))
        }
    }

    private static func path(_ keys: [any CodingKey]) -> String {
        keys.isEmpty ? "$" : keys.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
    }
}

// Package-only DTO decoding for importer headers. This does not grant the
// private runtime-document token or make numeric/reference Codable unchecked.
func decodeExactJSON<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    let decoder = JSONDecoder()
    _ = try decoder.decode(JSONSyntax.self, from: data)
    return try decoder.decode(type, from: ExactNumbers.prepare(data, invalidNumber: "{}"))
}

// JSONDecoder parses the JSON structure even when no fields are requested.
struct JSONSyntax: Decodable {
    init(from decoder: any Decoder) {}
}

/// Foundation's Int/Double/Decimal decoders can round fractional JSON numbers.
/// Keep strings untouched, and replace numeric tokens with their exact Int
/// spelling or a rejection sentinel. Raw matrices use null (rejected at the
/// matrix coordinate); runtime documents use {} so invalid numbers cannot turn
/// into valid nullable metadata. Importer DTOs share the same strict scan.
/// This changes neither accepted numeric values nor matrix ordering/edges.
enum ExactNumbers {
    static func prepare(_ data: Data, invalidNumber: String = "null") throws -> Data {
        let bytes = Array(data)
        var output = Data()
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let start = index
            if bytes[index] == 34 { // String: skip escaped quotes and backslashes.
                index += 1
                while index < bytes.count {
                    let byte = bytes[index]
                    index += 1
                    if byte == 92 { index += 1 }
                    else if byte == 34 { break }
                }
                guard index <= bytes.count else { throw RawConnectomeError.malformedJSON }
                output.append(contentsOf: bytes[start..<index])
            } else if (48...57).contains(bytes[index]) || [43, 45, 46].contains(bytes[index]) {
                while index < bytes.count && ((48...57).contains(bytes[index]) || [43, 45, 46, 69, 101].contains(bytes[index])) {
                    index += 1
                }
                let token = String(decoding: bytes[start..<index], as: UTF8.self)
                // Foundation defers some number grammar errors until conversion.
                guard token.wholeMatch(of: /-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/) != nil else {
                    throw RawConnectomeError.malformedJSON
                }
                let replacement = integer(token).map(String.init) ?? invalidNumber
                output.append(contentsOf: replacement.utf8)
            } else {
                // Foundation accepts trailing commas. Reject them outside strings,
                // including when JSON whitespace precedes a closing ] or }.
                if bytes[index] == 93 || bytes[index] == 125 {
                    let previous = bytes[..<index].last { ![9, 10, 13, 32].contains($0) }
                    guard previous != 44 else { throw RawConnectomeError.malformedJSON }
                }
                output.append(bytes[index])
                index += 1
            }
        }
        return output
    }

    private static func integer(_ token: String) -> Int? {
        let parts = token.split(whereSeparator: { $0 == "e" || $0 == "E" })
        let mantissa = parts[0]
        let digits = mantissa.filter { $0 != "-" && $0 != "." }.drop(while: { $0 == "0" })
        if digits.isEmpty { return 0 } // Signed zero, even with a huge exponent.
        guard !mantissa.hasPrefix("-") else { return nil }
        let fractionCount = mantissa.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        guard let exponent = parts.count == 2 ? Int(parts[1]) : 0 else { return nil }
        let (shift, overflow) = exponent.subtractingReportingOverflow(fractionCount)
        guard !overflow else { return nil }
        if shift < 0 {
            guard shift >= -digits.count, digits.suffix(-shift).allSatisfy({ $0 == "0" }) else { return nil }
            return Int(digits.dropLast(-shift))
        }
        // An Int has at most 19 decimal digits on supported macOS architectures.
        guard shift <= 19, digits.count <= 19 - shift else { return nil }
        return Int(String(digits) + String(repeating: "0", count: shift))
    }
}

private struct Source: Decodable {
    let nodes: [String]
    let chemical: [[Int]]
    let gapJunction: [[Int]]

    private enum CodingKeys: String, CodingKey {
        case nodes, connections
    }

    private struct MatrixKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = try container.decode([String].self, forKey: .nodes)
        var seen = Set<String>()
        for (index, id) in nodes.enumerated() {
            guard !id.isEmpty else { throw RawConnectomeError.emptyID(index: index) }
            guard seen.insert(id).inserted else { throw RawConnectomeError.duplicateID(id) }
        }

        let connections = try container.nestedContainer(keyedBy: MatrixKey.self, forKey: .connections)
        let supported = ["Generic_CS", "Generic_GJ"]
        // Sort error selection, rather than depending on JSON object key order.
        for name in connections.allKeys.map(\.stringValue).sorted() where !supported.contains(name) {
            throw RawConnectomeError.unsupportedMatrix(name)
        }
        for name in supported where !connections.contains(MatrixKey(stringValue: name)) {
            throw RawConnectomeError.missingMatrix(name)
        }
        chemical = try Self.matrix(connections, name: "Generic_CS", count: nodes.count)
        gapJunction = try Self.matrix(connections, name: "Generic_GJ", count: nodes.count)
        for row in nodes.indices {
            for column in (row + 1)..<nodes.count where gapJunction[row][column] != gapJunction[column][row] {
                throw RawConnectomeError.asymmetricGap(row: row, column: column)
            }
        }
    }

    private static func matrix(
        _ connections: KeyedDecodingContainer<MatrixKey>, name: String, count: Int
    ) throws -> [[Int]] {
        var rows = try connections.nestedUnkeyedContainer(forKey: MatrixKey(stringValue: name))
        var matrix: [[Int]] = []
        while !rows.isAtEnd {
            let row = rows.currentIndex
            var cells = try rows.nestedUnkeyedContainer()
            var values: [Int] = []
            while !cells.isAtEnd {
                let column = cells.currentIndex
                do {
                    values.append(try cells.decode(Int.self))
                } catch {
                    throw RawConnectomeError.invalidWeight(matrix: name, row: row, column: column)
                }
            }
            guard values.count == count else {
                throw RawConnectomeError.columnCount(matrix: name, row: row, expected: count, actual: values.count)
            }
            matrix.append(values)
        }
        guard matrix.count == count else {
            throw RawConnectomeError.rowCount(matrix: name, expected: count, actual: matrix.count)
        }
        return matrix
    }
}
