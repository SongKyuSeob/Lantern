import Foundation

/// 키 순서를 그대로 지키는 JSON 값.
///
/// 사용자가 직접 고치는 에이전트 설정 파일을 바꿀 때, 랜턴 hook 말고는 한 글자도 바뀌지 않게 하려고 쓴다.
/// `JSONSerialization`은 키 순서를 잃고 `"key" : value`처럼 써서 파일 전체가 바뀐다.
/// 출력 모양은 2칸 들여쓰기, `"key": value`, 비ASCII 글자는 그대로 (Claude Code·Codex 설정 파일과 같은 모양).
public indirect enum OrderedJSON: Equatable, Sendable {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// 원래 숫자 표기를 그대로 지킨다 (`1.0`이 `1`로 바뀌지 않게)
    case number(String)
    case bool(Bool)
    case null

    public static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(a), .object(b)):
            a.count == b.count && zip(a, b).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(a), .array(b)): a == b
        case let (.string(a), .string(b)): a == b
        case let (.number(a), .number(b)): a == b
        case let (.bool(a), .bool(b)): a == b
        case (.null, .null): true
        default: false
        }
    }

    // MARK: - 객체 다루기

    public subscript(key: String) -> OrderedJSON? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    /// 키가 있으면 그 자리에서 바꾸고, 없으면 끝에 더한다. `nil`이면 지운다
    public mutating func set(_ key: String, _ value: OrderedJSON?) {
        guard case .object(var members) = self else { return }
        if let index = members.firstIndex(where: { $0.key == key }) {
            if let value { members[index].value = value } else { members.remove(at: index) }
        } else if let value {
            members.append((key, value))
        }
        self = .object(members)
    }

    // MARK: - 읽기

    public enum ParseError: Error {
        case invalid(offset: Int)
    }

    public static func parse(_ text: String) throws -> OrderedJSON {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        parser.skipWhitespace()
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw ParseError.invalid(offset: parser.index) }
        return value
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0

        var isAtEnd: Bool { index >= scalars.count }

        mutating func skipWhitespace() {
            while !isAtEnd, [" ", "\n", "\r", "\t"].contains(scalars[index]) { index += 1 }
        }

        func fail() -> ParseError { .invalid(offset: index) }

        mutating func expect(_ scalar: Unicode.Scalar) throws {
            guard !isAtEnd, scalars[index] == scalar else { throw fail() }
            index += 1
        }

        mutating func expectWord(_ word: String) throws {
            for scalar in word.unicodeScalars { try expect(scalar) }
        }

        mutating func parseValue() throws -> OrderedJSON {
            guard !isAtEnd else { throw fail() }
            switch scalars[index] {
            case "{": return try parseObject()
            case "[": return try parseArray()
            case "\"": return .string(try parseString())
            case "t": try expectWord("true"); return .bool(true)
            case "f": try expectWord("false"); return .bool(false)
            case "n": try expectWord("null"); return .null
            default: return try parseNumber()
            }
        }

        mutating func parseObject() throws -> OrderedJSON {
            try expect("{")
            var members: [(key: String, value: OrderedJSON)] = []
            skipWhitespace()
            if !isAtEnd, scalars[index] == "}" { index += 1; return .object(members) }
            while true {
                skipWhitespace()
                let key = try parseString()
                skipWhitespace()
                try expect(":")
                skipWhitespace()
                members.append((key, try parseValue()))
                skipWhitespace()
                guard !isAtEnd else { throw fail() }
                if scalars[index] == "," { index += 1; continue }
                try expect("}")
                return .object(members)
            }
        }

        mutating func parseArray() throws -> OrderedJSON {
            try expect("[")
            var items: [OrderedJSON] = []
            skipWhitespace()
            if !isAtEnd, scalars[index] == "]" { index += 1; return .array(items) }
            while true {
                skipWhitespace()
                items.append(try parseValue())
                skipWhitespace()
                guard !isAtEnd else { throw fail() }
                if scalars[index] == "," { index += 1; continue }
                try expect("]")
                return .array(items)
            }
        }

        mutating func parseString() throws -> String {
            try expect("\"")
            var result = String.UnicodeScalarView()
            while true {
                guard !isAtEnd else { throw fail() }
                let scalar = scalars[index]
                index += 1
                switch scalar {
                case "\"":
                    return String(result)
                case "\\":
                    guard !isAtEnd else { throw fail() }
                    let escape = scalars[index]
                    index += 1
                    switch escape {
                    case "\"": result.append("\"")
                    case "\\": result.append("\\")
                    case "/": result.append("/")
                    case "b": result.append("\u{08}")
                    case "f": result.append("\u{0C}")
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "u": result.append(try parseUnicodeEscape())
                    default: throw fail()
                    }
                default:
                    guard scalar.value >= 0x20 else { throw fail() }
                    result.append(scalar)
                }
            }
        }

        mutating func parseHex4() throws -> UInt32 {
            guard index + 4 <= scalars.count,
                  let value = UInt32(String(String.UnicodeScalarView(scalars[index..<index + 4])), radix: 16)
            else { throw fail() }
            index += 4
            return value
        }

        /// `\uXXXX`. 서로게이트 짝(`😀`)도 한 글자로 합친다
        mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
            let high = try parseHex4()
            if (0xD800...0xDBFF).contains(high) {
                try expect("\\")
                try expect("u")
                let low = try parseHex4()
                guard (0xDC00...0xDFFF).contains(low),
                      let scalar = Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
                else { throw fail() }
                return scalar
            }
            guard let scalar = Unicode.Scalar(high) else { throw fail() }
            return scalar
        }

        mutating func parseNumber() throws -> OrderedJSON {
            let start = index
            while !isAtEnd, "+-0123456789.eE".unicodeScalars.contains(scalars[index]) { index += 1 }
            let text = String(String.UnicodeScalarView(scalars[start..<index]))
            guard !text.isEmpty, Double(text) != nil else { throw fail() }
            return .number(text)
        }
    }

    // MARK: - 쓰기

    /// 2칸 들여쓰기로 쓴 글. 끝에 줄바꿈을 붙인다
    public func formatted() -> String {
        var output = ""
        write(into: &output, indent: 0)
        return output + "\n"
    }

    private func write(into output: inout String, indent: Int) {
        let padding = String(repeating: "  ", count: indent + 1)
        let closing = String(repeating: "  ", count: indent)
        switch self {
        case .object(let members):
            guard !members.isEmpty else { output += "{}"; return }
            output += "{\n"
            for (offset, member) in members.enumerated() {
                output += padding + Self.quoted(member.key) + ": "
                member.value.write(into: &output, indent: indent + 1)
                output += offset < members.count - 1 ? ",\n" : "\n"
            }
            output += closing + "}"
        case .array(let items):
            guard !items.isEmpty else { output += "[]"; return }
            output += "[\n"
            for (offset, item) in items.enumerated() {
                output += padding
                item.write(into: &output, indent: indent + 1)
                output += offset < items.count - 1 ? ",\n" : "\n"
            }
            output += closing + "]"
        case .string(let value): output += Self.quoted(value)
        case .number(let text): output += text
        case .bool(let value): output += value ? "true" : "false"
        case .null: output += "null"
        }
    }

    private static func quoted(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}
