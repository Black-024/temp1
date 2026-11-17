import Foundation

/// JSON mínimo, con objetos ORDENADOS. La salida imita a `json.dumps(..., ensure_ascii=False)` de Python
/// (separadores «, » y «: ») porque el texto original de cada respuesta se guarda con ese formato y debe ser
/// idéntico al de la versión de escritorio y de Android.
public struct JObject: Equatable {
    public private(set) var keys: [String] = []
    private var dict: [String: JSON] = [:]
    public init() {}
    public subscript(key: String) -> JSON? {
        get { dict[key] }
        set {
            if let v = newValue {
                if dict[key] == nil { keys.append(key) }
                dict[key] = v
            } else if dict[key] != nil {
                dict[key] = nil; keys.removeAll { $0 == key }
            }
        }
    }
    public var count: Int { keys.count }
    public var entries: [(String, JSON)] { keys.map { ($0, dict[$0]!) } }
}

public indirect enum JSON: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSON])
    case object(JObject)

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var intValue: Int? {
        switch self { case .int(let i): return Int(i); case .double(let d): return d == d.rounded() ? Int(d) : nil; default: return nil }
    }
    public var doubleValue: Double? {
        switch self { case .int(let i): return Double(i); case .double(let d): return d; default: return nil }
    }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [JSON]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: JObject? { if case .object(let o) = self { return o }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }
    public subscript(key: String) -> JSON? { objectValue?[key] }
}

public struct JsonParseError: Error, CustomStringConvertible {
    public let description: String
    init(_ m: String) { description = m }
}

public enum Json {
    public static func parse(_ text: String) throws -> JSON {
        var p = Parser(Array(text.utf16))
        p.skipWs()
        let v = try p.value()
        p.skipWs()
        if !p.atEnd { throw JsonParseError("Texto sobrante después del JSON") }
        return v
    }

    public static func parseObject(_ text: String) throws -> JObject {
        guard case .object(let o) = try parse(text) else { throw JsonParseError("Se esperaba un objeto JSON") }
        return o
    }

    public static func stringify(_ v: JSON) -> String {
        var out = ""
        write(&out, v)
        return out
    }

    private static func write(_ sb: inout String, _ v: JSON) {
        switch v {
        case .null: sb += "null"
        case .bool(let b): sb += b ? "true" : "false"
        case .int(let i): sb += String(i)
        case .double(let d):
            if d == d.rounded(.down) && d.isFinite && abs(d) < 1e15 { sb += "\(Int64(d)).0" } else { sb += "\(d)" }
        case .string(let s): quote(&sb, s)
        case .object(let o):
            sb += "{"
            var first = true
            for (k, x) in o.entries {
                if !first { sb += ", " }
                first = false
                quote(&sb, k); sb += ": "; write(&sb, x)
            }
            sb += "}"
        case .array(let a):
            sb += "["
            var first = true
            for x in a {
                if !first { sb += ", " }
                first = false
                write(&sb, x)
            }
            sb += "]"
        }
    }

    private static func quote(_ sb: inout String, _ s: String) {
        sb += "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": sb += "\\\""
            case "\\": sb += "\\\\"
            case "\n": sb += "\\n"
            case "\r": sb += "\\r"
            case "\t": sb += "\\t"
            case "\u{08}": sb += "\\b"
            case "\u{0C}": sb += "\\f"
            default:
                if c.value < 0x20 { sb += String(format: "\\u%04x", c.value) } else { sb.unicodeScalars.append(c) }
            }
        }
        sb += "\""
    }

    private struct Parser {
        let s: [UInt16]
        var i = 0
        init(_ s: [UInt16]) { self.s = s }
        var atEnd: Bool { i >= s.count }
        mutating func skipWs() { while i < s.count, s[i] == 32 || s[i] == 10 || s[i] == 13 || s[i] == 9 { i += 1 } }
        func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }

        mutating func value() throws -> JSON {
            if atEnd { throw JsonParseError("JSON incompleto") }
            switch s[i] {
            case 123: return try obj()
            case 91: return try arr()
            case 34: return .string(try str())
            case 116: return try lit("true", .bool(true))
            case 102: return try lit("false", .bool(false))
            case 110: return try lit("null", .null)
            default:
                if s[i] == 45 || isDigit(s[i]) { return try num() }
                throw JsonParseError("Carácter inesperado en \(i)")
            }
        }

        mutating func lit(_ word: String, _ v: JSON) throws -> JSON {
            let w = Array(word.utf16)
            if i + w.count > s.count || Array(s[i..<i + w.count]) != w { throw JsonParseError("Valor inválido en \(i)") }
            i += w.count
            return v
        }

        mutating func obj() throws -> JSON {
            var m = JObject()
            i += 1; skipWs()
            if i < s.count, s[i] == 125 { i += 1; return .object(m) }
            while true {
                skipWs()
                if i >= s.count || s[i] != 34 { throw JsonParseError("Se esperaba una clave en \(i)") }
                let k = try str(); skipWs()
                if i >= s.count || s[i] != 58 { throw JsonParseError("Se esperaba ':' en \(i)") }
                i += 1; skipWs()
                m[k] = try value(); skipWs()
                if i >= s.count { throw JsonParseError("Objeto sin cerrar") }
                if s[i] == 44 { i += 1; continue }
                if s[i] == 125 { i += 1; return .object(m) }
                throw JsonParseError("Se esperaba ',' o '}' en \(i)")
            }
        }

        mutating func arr() throws -> JSON {
            var l: [JSON] = []
            i += 1; skipWs()
            if i < s.count, s[i] == 93 { i += 1; return .array(l) }
            while true {
                skipWs(); l.append(try value()); skipWs()
                if i >= s.count { throw JsonParseError("Lista sin cerrar") }
                if s[i] == 44 { i += 1; continue }
                if s[i] == 93 { i += 1; return .array(l) }
                throw JsonParseError("Se esperaba ',' o ']' en \(i)")
            }
        }

        mutating func str() throws -> String {
            var buf: [UInt16] = []
            i += 1
            while true {
                if i >= s.count { throw JsonParseError("Texto sin cerrar") }
                let c = s[i]; i += 1
                if c == 34 { return String(decoding: buf, as: UTF16.self) }
                if c != 92 { buf.append(c); continue }
                if i >= s.count { throw JsonParseError("Escape incompleto") }
                let e = s[i]; i += 1
                switch e {
                case 34: buf.append(34)
                case 92: buf.append(92)
                case 47: buf.append(47)
                case 98: buf.append(8)
                case 102: buf.append(12)
                case 110: buf.append(10)
                case 114: buf.append(13)
                case 116: buf.append(9)
                case 117:
                    if i + 4 > s.count { throw JsonParseError("Escape \\u incompleto") }
                    guard let n = UInt16(String(decoding: s[i..<i + 4], as: UTF16.self), radix: 16) else { throw JsonParseError("Escape \\u inválido") }
                    buf.append(n); i += 4
                default: throw JsonParseError("Escape inválido")
                }
            }
        }

        mutating func num() throws -> JSON {
            let start = i
            if s[i] == 45 { i += 1 }
            while i < s.count, isDigit(s[i]) { i += 1 }
            var real = false
            if i < s.count, s[i] == 46 { real = true; i += 1; while i < s.count, isDigit(s[i]) { i += 1 } }
            if i < s.count, s[i] == 101 || s[i] == 69 {
                real = true; i += 1
                if i < s.count, s[i] == 43 || s[i] == 45 { i += 1 }
                while i < s.count, isDigit(s[i]) { i += 1 }
            }
            let t = String(decoding: s[start..<i], as: UTF16.self)
            if !real, let n = Int64(t) { return .int(n) }
            guard let d = Double(t) else { throw JsonParseError("Número inválido en \(start)") }
            return .double(d)
        }
    }
}
