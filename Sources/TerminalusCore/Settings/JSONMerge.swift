import Foundation

public enum SettingsCodingError: LocalizedError {
    case notAnObject
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .notAnObject: "settings.json must contain a JSON object at the top level."
        case .decoding(let s): s
        }
    }
}

public enum JSONMerge {
    /// Recursively merges `overlay` into `base`: objects merge key by key, everything else (arrays,
    /// scalars, null) in `overlay` replaces the base value.
    public static func merge(_ base: Any, _ overlay: Any) -> Any {
        guard let b = base as? [String: Any], let o = overlay as? [String: Any] else { return overlay }
        var out = b
        for (k, v) in o {
            if let existing = out[k] {
                out[k] = merge(existing, v)
            } else {
                out[k] = v
            }
        }
        return out
    }

    /// Decodes `data` merged over the encoded defaults of `T()`, so missing keys fall back to defaults.
    public static func decodeMerged<T: Codable>(_ type: T.Type, from data: Data, defaults: T) throws -> T {
        let parsed = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard parsed is [String: Any] else { throw SettingsCodingError.notAnObject }
        let baseData = try JSONEncoder().encode(defaults)
        let base = try JSONSerialization.jsonObject(with: baseData)
        let merged = merge(base, parsed)
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        do {
            return try JSONDecoder().decode(T.self, from: mergedData)
        } catch let DecodingError.dataCorrupted(ctx) {
            throw SettingsCodingError.decoding("Invalid value at \(pathString(ctx.codingPath)): \(ctx.debugDescription)")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw SettingsCodingError.decoding("Wrong type at \(pathString(ctx.codingPath)): \(ctx.debugDescription)")
        } catch let DecodingError.valueNotFound(_, ctx) {
            throw SettingsCodingError.decoding("Missing value at \(pathString(ctx.codingPath)): \(ctx.debugDescription)")
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw SettingsCodingError.decoding("Missing key \"\(key.stringValue)\" at \(pathString(ctx.codingPath))")
        }
    }

    public static func prettyEncode<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try enc.encode(value)
    }

    private static func pathString(_ path: [CodingKey]) -> String {
        path.isEmpty ? "top level" : path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
}
