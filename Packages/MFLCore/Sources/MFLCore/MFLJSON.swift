import Foundation

/// A lossless-enough representation of MFL's loosely typed JSON fields.
///
/// MFL commonly encodes numbers and booleans as strings, and occasionally adds
/// endpoint-specific keys. Models expose important fields as concrete types and
/// retain those extra fields as `MFLJSONValue` where doing so is useful.
public enum MFLJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: MFLJSONValue])
    case array([MFLJSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: MFLJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([MFLJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.typeMismatch(
                MFLJSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    /// A scalar string, including MFL's conventional `{ "$t": "..." }` text object.
    public var stringValue: String? {
        switch self {
        case let .string(value):
            value
        case let .number(value):
            if value.rounded() == value,
               value >= Double(Int.min),
               value <= Double(Int.max)
            {
                String(Int(value))
            } else {
                String(value)
            }
        case let .bool(value):
            value ? "1" : "0"
        case let .object(value):
            value["$t"]?.stringValue
        case .array, .null:
            nil
        }
    }

    public var objectValue: [String: MFLJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    public var arrayValue: [MFLJSONValue]? {
        switch self {
        case let .array(value): value
        case .null: []
        default: [self]
        }
    }
}

/// Decodes either a JSON array, one object, or `null` into a predictable array.
public struct MFLOneOrMany<Element: Codable & Sendable>: Codable, Sendable {
    public var values: [Element]

    public init(_ values: [Element]) {
        self.values = values
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            values = []
        } else if let many = try? container.decode([Element].self) {
            values = many
        } else {
            values = [try container.decode(Element.self)]
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

struct MFLDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension KeyedDecodingContainer {
    func mflStringIfPresent(forKey key: Key) throws -> String? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? "1" : "0" }
        return try decode(MFLJSONValue.self, forKey: key).stringValue
    }

    func mflRequiredString(forKey key: Key) throws -> String {
        guard let value = try mflStringIfPresent(forKey: key), !value.isEmpty else {
            throw DecodingError.valueNotFound(
                String.self,
                .init(codingPath: codingPath + [key], debugDescription: "Expected a non-empty MFL string")
            )
        }
        return value
    }

    func mflIntIfPresent(forKey key: Key) throws -> Int? {
        guard let string = try mflStringIfPresent(forKey: key) else { return nil }
        return Int(string)
    }

    func mflDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard let string = try mflStringIfPresent(forKey: key) else { return nil }
        return Double(string.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: ""))
    }

    func mflDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        guard let string = try mflStringIfPresent(forKey: key) else { return nil }
        let normalized = string
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    func mflBoolIfPresent(forKey key: Key) throws -> Bool? {
        guard let value = try mflStringIfPresent(forKey: key)?.lowercased() else { return nil }
        switch value {
        case "1", "true", "yes", "y": return true
        case "0", "false", "no", "n": return false
        default: return nil
        }
    }

    func mflArray<T: Decodable>(of type: T.Type, forKey key: Key) throws -> [T] {
        guard contains(key), try !decodeNil(forKey: key) else { return [] }
        if let values = try? decode([T].self, forKey: key) { return values }
        return [try decode(T.self, forKey: key)]
    }
}

extension Dictionary where Key == String, Value == MFLJSONValue {
    func mflString(_ keys: String...) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue { return value }
        }
        return nil
    }

    func mflInt(_ keys: String...) -> Int? {
        guard let value = mflString(keys) else { return nil }
        return Int(value)
    }

    func mflDecimal(_ keys: String...) -> Decimal? {
        guard let value = mflString(keys) else { return nil }
        return Decimal(
            string: value.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ""),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func mflString(_ keys: [String]) -> String? {
        for key in keys {
            if let value = self[key]?.stringValue { return value }
        }
        return nil
    }
}
