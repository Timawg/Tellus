import CoreGraphics
import Foundation

struct PowerGridAsset: Identifiable {
    enum Kind: String, CaseIterable {
        case line = "Power line"
        case substation = "Substation"
        case plant = "Power plant"

        init?(layer: String) {
            switch layer {
            case "power_line": self = .line
            case "power_substation", "power_substation_point": self = .substation
            case "power_plant", "power_plant_point": self = .plant
            default: return nil
            }
        }
    }

    let kind: Kind
    let osmID: Int64
    let isNode: Bool
    let name: String?
    let operatorName: String?
    let voltage: Double?
    let energySource: String?

    var id: URL { sourceURL }
    var sourceURL: URL {
        let type = osmID < 0 ? "relation" : isNode ? "node" : "way"
        return URL(string: "https://www.openstreetmap.org/\(type)/\(osmID.magnitude)")!
    }
}

/// The power layers in Open Infrastructure Map's Mapbox Vector Tile response.
struct PowerGridTile {
    static let size = 256

    struct Feature {
        let kind: PowerGridAsset.Kind
        let geometry: Geometry
        let path: CGPath
        let asset: PowerGridAsset?

        enum Geometry: UInt64 {
            case point = 1
            case line = 2
            case area = 3
        }
    }

    let features: [Feature]

    init(data: Data) throws {
        var tile = ProtobufReader(data)
        var features: [Feature] = []
        while let (field, value) = try tile.readField() {
            if field == 3, case .bytes(let layer) = value {
                features += try Self.readLayer(layer)
            }
        }
        self.features = features
    }

    func asset(at point: CGPoint, tolerance: CGFloat) -> PowerGridAsset? {
        // Hit-test in reverse draw order so a plant or substation wins over
        // a line drawn underneath it.
        for kind in PowerGridAsset.Kind.allCases.reversed() {
            for feature in features.reversed() where feature.kind == kind {
                guard let asset = feature.asset,
                      feature.path.boundingBoxOfPath.insetBy(dx: -tolerance, dy: -tolerance).contains(point) else { continue }
                if feature.geometry != .line, feature.path.contains(point, using: .evenOdd) {
                    return asset
                }
                if feature.geometry != .area,
                   feature.path.copy(strokingWithWidth: tolerance * 2, lineCap: .round, lineJoin: .round, miterLimit: 1)
                    .contains(point) {
                    return asset
                }
            }
        }
        return nil
    }

    private static func readLayer(_ data: Data) throws -> [Feature] {
        var layer = ProtobufReader(data)
        var kind: PowerGridAsset.Kind?
        var extent = 4096
        var features: [Data] = []
        var keys: [String] = []
        var values: [TileValue] = []
        while let (field, value) = try layer.readField() {
            switch (field, value) {
            case (1, .bytes(let name)): kind = PowerGridAsset.Kind(layer: String(decoding: name, as: UTF8.self))
            case (2, .bytes(let feature)): features.append(feature)
            case (3, .bytes(let key)): keys.append(String(decoding: key, as: UTF8.self))
            case (4, .bytes(let value)): values.append(try TileValue(data: value))
            case (5, .integer(let value)): extent = Int(exactly: value) ?? 0
            default: break
            }
        }
        guard let kind else { return [] }
        guard extent > 0 else { throw TileError.invalidTile }
        return try features.compactMap { try readFeature($0, kind: kind, extent: extent, keys: keys, values: values) }
    }

    private static func readFeature(
        _ data: Data, kind: PowerGridAsset.Kind, extent: Int, keys: [String], values: [TileValue]
    ) throws -> Feature? {
        var feature = ProtobufReader(data)
        var geometry: Feature.Geometry?
        var commands: Data?
        var attributes: [String: TileValue] = [:]
        while let (field, value) = try feature.readField() {
            switch (field, value) {
            case (2, .bytes(let tags)):
                var tags = ProtobufReader(tags)
                while !tags.isAtEnd {
                    let keyIndex = try tags.readInteger()
                    let valueIndex = try tags.readInteger()
                    guard keyIndex < keys.count, valueIndex < values.count else { throw TileError.invalidTile }
                    attributes[keys[Int(keyIndex)]] = values[Int(valueIndex)]
                }
            case (3, .integer(let value)): geometry = Feature.Geometry(rawValue: value)
            case (4, .bytes(let value)): commands = value
            default: break
            }
        }
        guard let geometry, let commands else { return nil }

        let asset = attributes["osm_id"]?.integer.flatMap { id -> PowerGridAsset? in
            guard id != 0 else { return nil }
            return PowerGridAsset(
                kind: kind, osmID: id, isNode: attributes["is_node"]?.integer == 1,
                name: attributes["name"]?.text, operatorName: attributes["operator"]?.text,
                voltage: attributes["voltage"]?.number, energySource: attributes["source"]?.text
            )
        }
        let path = try readPath(commands, geometry: geometry, scale: CGFloat(size) / CGFloat(extent), kind: kind)
        return Feature(kind: kind, geometry: geometry, path: path, asset: asset)
    }

    private static func readPath(
        _ data: Data, geometry: Feature.Geometry, scale: CGFloat, kind: PowerGridAsset.Kind
    ) throws -> CGPath {
        var commands = ProtobufReader(data)
        let path = CGMutablePath()
        var x: CGFloat = 0
        var y: CGFloat = 0
        while !commands.isAtEnd {
            let command = try commands.readInteger()
            let action = command & 7
            let count = command >> 3
            if action == 7, count == 1 {
                path.closeSubpath()
                continue
            }
            guard (action == 1 || action == 2), count > 0, count <= commands.remaining / 2 else {
                throw TileError.invalidTile
            }
            for _ in 0..<count {
                x += CGFloat(ProtobufReader.signed(try commands.readInteger()))
                y += CGFloat(ProtobufReader.signed(try commands.readInteger()))
                let point = CGPoint(x: x * scale, y: y * scale)
                if geometry == .point {
                    let radius: CGFloat = kind == .plant ? 4 : 2.5
                    path.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                } else if action == 1 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
        return path
    }

    private struct TileValue {
        var text: String?
        var integer: Int64?
        private var floatingPoint: Double?

        var number: Double? { floatingPoint ?? integer.map(Double.init) ?? text.flatMap(Double.init) }

        init(data: Data) throws {
            var value = ProtobufReader(data)
            guard let (field, payload) = try value.readField() else { return }
            switch (field, payload) {
            case (1, .bytes(let bytes)):
                let string = String(decoding: bytes, as: UTF8.self)
                text = string.isEmpty ? nil : string
            case (2, .fixed(let bits)): floatingPoint = Double(Float(bitPattern: UInt32(truncatingIfNeeded: bits)))
            case (3, .fixed(let bits)): floatingPoint = Double(bitPattern: bits)
            case (4, .integer(let bits)), (5, .integer(let bits)), (7, .integer(let bits)):
                integer = Int64(bitPattern: bits)
            case (6, .integer(let bits)): integer = ProtobufReader.signed(bits)
            default: break
            }
        }
    }
}

private enum TileError: Error {
    case invalidTile
}

/// Reads the protobuf wire types used by the Mapbox Vector Tile format.
private struct ProtobufReader {
    enum Value {
        case integer(UInt64)
        case bytes(Data)
        case fixed(UInt64)
    }

    private let data: Data
    private var position: Int

    init(_ data: Data) {
        self.data = data
        self.position = data.startIndex
    }

    var remaining: Int { data.endIndex - position }
    var isAtEnd: Bool { remaining == 0 }

    mutating func readField() throws -> (UInt64, Value)? {
        guard !isAtEnd else { return nil }
        let tag = try readInteger()
        guard tag >> 3 > 0 else { throw TileError.invalidTile }
        let value: Value
        switch tag & 7 {
        case 0: value = .integer(try readInteger())
        case 1: value = .fixed(try readFixed(count: 8))
        case 2:
            let count = try readInteger()
            guard count <= remaining else { throw TileError.invalidTile }
            let start = position
            position += Int(count)
            value = .bytes(data[start..<position])
        case 5: value = .fixed(try readFixed(count: 4))
        default: throw TileError.invalidTile
        }
        return (tag >> 3, value)
    }

    mutating func readInteger() throws -> UInt64 {
        var value: UInt64 = 0
        for shift in stride(from: 0, through: 63, by: 7) {
            guard !isAtEnd else { throw TileError.invalidTile }
            let byte = data[position]
            position += 1
            guard shift != 63 || byte <= 1 else { throw TileError.invalidTile }
            value |= UInt64(byte & 127) << shift
            if byte < 128 { return value }
        }
        throw TileError.invalidTile
    }

    private mutating func readFixed(count: Int) throws -> UInt64 {
        guard remaining >= count else { throw TileError.invalidTile }
        var value: UInt64 = 0
        for offset in 0..<count {
            value |= UInt64(data[position + offset]) << (offset * 8)
        }
        position += count
        return value
    }

    static func signed(_ value: UInt64) -> Int64 {
        Int64(bitPattern: (value >> 1) ^ (0 &- (value & 1)))
    }
}
