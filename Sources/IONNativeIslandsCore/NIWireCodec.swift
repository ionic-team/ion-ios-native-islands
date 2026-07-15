import Foundation
import CoreFoundation

/// Canonical JSON for byte-addressed bridge paths. Foundation's sorted-key writer
/// is shared by the T1 response path and cross-language golden-vector tests.
public enum NIWireCodec {
    public static func encode(_ value: Any) throws -> Data {
        Data(try encodeValue(value).utf8)
    }

    public static func encodeString(_ value: Any) throws -> String {
        let data = try encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NIBridgeSecurityError("internal_error", "wire encoder produced non-UTF-8 data")
        }
        return string
    }

    public static func decode(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private static func encodeValue(_ value: Any) throws -> String {
        if value is NSNull { return "null" }
        if let string = value as? String { return quote(string) }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let type = String(cString: number.objCType)
            if "csilq".contains(type) { return String(number.int64Value) }
            if "CSILQ".contains(type) { return String(number.uint64Value) }
            let double = number.doubleValue
            guard double.isFinite else {
                throw NIBridgeSecurityError("invalid_request", "wire numbers must be finite")
            }
            if double == 0 { return "0" }
            return String(double).replacingOccurrences(of: "E", with: "e")
        }
        if let array = value as? [Any] {
            return "[" + (try array.map(encodeValue)).joined(separator: ",") + "]"
        }
        if let object = value as? [String: Any] {
            let pairs = try object.keys.sorted().map { key in
                quote(key) + ":" + (try encodeValue(object[key]!))
            }
            return "{" + pairs.joined(separator: ",") + "}"
        }
        throw NIBridgeSecurityError("invalid_request", "wire value must be JSON-compatible")
    }

    private static func quote(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: result += "\\b"
            case 0x09: result += "\\t"
            case 0x0A: result += "\\n"
            case 0x0C: result += "\\f"
            case 0x0D: result += "\\r"
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x00...0x1F:
                result += String(format: "\\u%04x", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }
}
