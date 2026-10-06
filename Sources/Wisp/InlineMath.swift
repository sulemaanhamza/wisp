import Foundation

/// Inline calculations. A line that ends in `=` gets its answer drawn
/// after it — `12 × 4.5 + 20 =` shows 74, `5 km in mi =` shows 3.11 mi —
/// without the answer ever being written to the file. Tab types it in.
///
/// Pure and line-local: a line's answer depends on nothing but the line,
/// which is what lets the paragraph restyle compute it.
///
/// Deliberately a small hand-written parser rather than NSExpression:
/// that one raises Objective-C exceptions on malformed input and will
/// happily call functions named in the string.
@MainActor
enum InlineMath {
    /// The answer to show after `line`, or nil when the line doesn't end
    /// in `=` or holds nothing worth calculating.
    static func answer(forLine line: String) -> String? {
        guard let body = expressionText(line) else { return nil }
        // The expression is the longest tail of the line that parses, so
        // "Rent: 1200 / 3 =" and "split 1200 / 3 =" both find 1200 / 3.
        let ns = body as NSString
        var starts = [0]
        for i in 0..<ns.length where i > 0 && isSpace(ns.character(at: i - 1)) && !isSpace(ns.character(at: i)) {
            starts.append(i)
        }
        for start in starts {
            let candidate = ns.substring(from: start)
            if let answer = evaluate(candidate) { return answer }
        }
        return nil
    }

    private static let marker = try! NSRegularExpression(
        pattern: #"^\s*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+|>\s+|#{1,6}\s+)?"#
    )

    /// The text before a trailing `=`, with any list, quote or heading
    /// marker taken off. Nil unless the line really ends in a lone `=`:
    /// `==`, `<=`, `!=` and `=>` are code, not a question.
    static func expressionText(_ line: String) -> String? {
        var text = line
        while let last = text.unicodeScalars.last, CharacterSet.whitespaces.contains(last) {
            text.unicodeScalars.removeLast()
        }
        guard text.hasSuffix("=") else { return nil }
        text.removeLast()
        if let before = text.last, "=!<>".contains(before) { return nil }
        let ns = text as NSString
        let stripped = marker.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(from: NSMaxRange($0.range)) } ?? text
        let trimmed = stripped.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The formatted answer for a whole expression, or nil when it
    /// doesn't parse or has no operation in it — `42 =` isn't a sum.
    static func evaluate(_ expression: String) -> String? {
        // 2026-09-25 is a date, not a subtraction.
        if expression.range(of: #"\b\d{4}-\d{1,2}-\d{1,2}\b"#, options: .regularExpression) != nil {
            return nil
        }
        guard let tokens = tokenize(expression) else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseStatement(), parser.isAtEnd, parser.didOperate else { return nil }
        return format(value)
    }

    // MARK: Values

    enum Value {
        case number(Double)
        /// `15%` — a fraction that knows it was written as a percentage,
        /// so `150 + 15%` can mean 172.5.
        case percent(Double)
        case quantity(Double, Dimension)

        var scalar: Double? {
            switch self {
            case .number(let n): return n
            case .percent(let p): return p / 100
            case .quantity: return nil
            }
        }
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double)
        case symbol(Character)
        case word(String)
    }

    private static let keywords: Set<String> = ["in", "to", "as", "of", "x"]

    static func tokenize(_ text: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(text)
        let n = chars.count
        func isDigit(_ i: Int) -> Bool { i < n && chars[i].isASCII && chars[i].isNumber }
        // "1,200" but not "1,2" or "1,2000": exactly three digits follow.
        func isThousandsComma(_ i: Int) -> Bool {
            chars[i] == "," && isDigit(i + 1) && isDigit(i + 2) && isDigit(i + 3) && !isDigit(i + 4)
        }
        var i = 0
        while i < n {
            let c = chars[i]
            if c == " " || c == "\t" {
                i += 1
            } else if isDigit(i) || (c == "." && isDigit(i + 1)) {
                var digits = ""
                while i < n {
                    if isDigit(i) || chars[i] == "." {
                        digits.append(chars[i])
                        i += 1
                    } else if isThousandsComma(i) {
                        i += 1
                    } else {
                        break
                    }
                }
                guard let value = Double(digits) else { return nil }
                tokens.append(.number(value))
            } else if "+-*/^()%×÷−".contains(c) {
                let normalised: Character = c == "×" ? "*" : c == "÷" ? "/" : c == "−" ? "-" : c
                tokens.append(.symbol(normalised))
                i += 1
            } else if c.isLetter || c == "°" {
                var word = ""
                while i < n, chars[i].isLetter || chars[i] == "°" {
                    word.append(chars[i])
                    i += 1
                }
                // Words that mean something to the maths are kept; the
                // rest are labels — "4 nights × 120", "3 apples + 2" —
                // and read as if they weren't there.
                let lower = word.lowercased()
                if keywords.contains(lower) || Units.unit(named: lower) != nil {
                    tokens.append(.word(lower))
                }
            } else {
                return nil
            }
        }
        return tokens
    }

    // MARK: Parser

    @MainActor
    struct Parser {
        let tokens: [Token]
        var index = 0
        /// Whether anything was actually worked out. A bare number
        /// followed by `=` is left alone.
        var didOperate = false

        init(tokens: [Token]) { self.tokens = tokens }

        var isAtEnd: Bool { index >= tokens.count }
        private var peek: Token? { index < tokens.count ? tokens[index] : nil }

        private mutating func take(_ symbol: Character) -> Bool {
            if peek == .symbol(symbol) { index += 1; return true }
            return false
        }

        private mutating func takeWord(_ words: Set<String>) -> Bool {
            if case .word(let w)? = peek, words.contains(w) { index += 1; return true }
            return false
        }

        /// expression [in|to|as unit]
        mutating func parseStatement() -> Value? {
            guard var value = parseSum() else { return nil }
            if takeWord(["in", "to", "as"]) {
                guard case .word(let name)? = peek, let target = Units.unit(named: name) else { return nil }
                index += 1
                guard case .quantity(let amount, let unit) = value,
                      let converted = Units.convert(amount, from: unit, to: target) else { return nil }
                value = .quantity(converted, target)
                didOperate = true
            }
            return value
        }

        private mutating func parseSum() -> Value? {
            guard var left = parseProduct() else { return nil }
            while true {
                let sign: Double
                if take("+") { sign = 1 } else if take("-") { sign = -1 } else { return left }
                guard let right = parseProduct() else { return nil }
                didOperate = true
                guard let combined = Self.add(left, right, sign: sign) else { return nil }
                left = combined
            }
        }

        private mutating func parseProduct() -> Value? {
            guard var left = parsePower() else { return nil }
            while true {
                let dividing: Bool
                if take("*") || takeWord(["x"]) { dividing = false } else if take("/") { dividing = true } else { return left }
                guard let right = parsePower() else { return nil }
                didOperate = true
                guard let combined = Self.multiply(left, right, dividing: dividing) else { return nil }
                left = combined
            }
        }

        private mutating func parsePower() -> Value? {
            guard let base = parseUnary() else { return nil }
            guard take("^") else { return base }
            guard let exponent = parsePower(), let b = base.scalar, let e = exponent.scalar else { return nil }
            didOperate = true
            return .number(pow(b, e))
        }

        private mutating func parseUnary() -> Value? {
            if take("-") {
                guard let value = parseUnary() else { return nil }
                switch value {
                case .number(let n): return .number(-n)
                case .percent(let p): return .percent(-p)
                case .quantity(let q, let u): return .quantity(-q, u)
                }
            }
            if take("+") { return parseUnary() }
            return parsePostfix()
        }

        /// A number or group, then an optional `%` (and `of …`) or unit.
        private mutating func parsePostfix() -> Value? {
            guard let primary = parsePrimary() else { return nil }
            if take("%") {
                guard let p = primary.scalar else { return nil }
                if takeWord(["of"]) {
                    guard let whole = parsePower() else { return nil }
                    didOperate = true
                    return Self.multiply(.number(p / 100), whole, dividing: false)
                }
                return .percent(p)
            }
            if case .number(let n) = primary, case .word(let name)? = peek, let unit = Units.unit(named: name) {
                index += 1
                return .quantity(n, unit)
            }
            return primary
        }

        private mutating func parsePrimary() -> Value? {
            if case .number(let n)? = peek {
                index += 1
                return .number(n)
            }
            if take("(") {
                guard let inner = parseSum(), take(")") else { return nil }
                return inner
            }
            return nil
        }

        static func add(_ a: Value, _ b: Value, sign: Double) -> Value? {
            switch (a, b) {
            case (.quantity(let x, let u), .quantity(let y, let v)):
                guard let y2 = Units.convert(y, from: v, to: u) else { return nil }
                return .quantity(x + sign * y2, u)
            // 150 + 15% is 150 grown by 15%, as on a till receipt.
            case (.number(let x), .percent(let p)):
                return .number(x * (1 + sign * p / 100))
            case (.quantity(let x, let u), .percent(let p)):
                return .quantity(x * (1 + sign * p / 100), u)
            case (.percent(let p), .percent(let q)):
                return .percent(p + sign * q)
            default:
                guard let x = a.scalar, let y = b.scalar else { return nil }
                return .number(x + sign * y)
            }
        }

        static func multiply(_ a: Value, _ b: Value, dividing: Bool) -> Value? {
            switch (a, b) {
            case (.quantity(let x, let u), _):
                guard let y = b.scalar ?? Self.sameUnitRatio(b, u) else { return nil }
                if case .quantity = b {
                    // km / km is a plain ratio; km × km isn't supported.
                    return dividing && y != 0 ? .number(x / y) : nil
                }
                if dividing { return y == 0 ? nil : .quantity(x / y, u) }
                return .quantity(x * y, u)
            case (_, .quantity(let y, let u)):
                guard !dividing, let x = a.scalar else { return nil }
                return .quantity(x * y, u)
            default:
                guard let x = a.scalar, let y = b.scalar else { return nil }
                if dividing { return y == 0 ? nil : .number(x / y) }
                return .number(x * y)
            }
        }

        private static func sameUnitRatio(_ value: Value, _ unit: Dimension) -> Double? {
            guard case .quantity(let y, let v) = value else { return nil }
            return Units.convert(y, from: v, to: unit)
        }
    }

    // MARK: Output

    static func format(_ value: Value) -> String? {
        switch value {
        case .number(let n):
            return formatNumber(n, maxFraction: 6)
        case .percent(let p):
            return formatNumber(p, maxFraction: 4).map { $0 + "%" }
        case .quantity(let q, let unit):
            let digits = abs(q) < 1 ? 4 : 2
            return formatNumber(q, maxFraction: digits).map { "\($0) \(Units.symbol(for: unit))" }
        }
    }

    static func formatNumber(_ n: Double, maxFraction: Int) -> String? {
        guard n.isFinite else { return nil }
        let formatter = NumberFormatter()
        // Always "1,234.5": the same notation the parser reads back.
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFraction
        let text = formatter.string(from: NSNumber(value: n))
        return text == "-0" ? "0" : text
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }
}

/// The units conversions understand, by the names people type.
@MainActor
enum Units {
    private static let day = UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400))
    private static let week = UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800))

    private static let table: [(names: [String], unit: Dimension, symbol: String)] = [
        (["km", "kilometer", "kilometers", "kilometre", "kilometres"], UnitLength.kilometers, "km"),
        (["m", "meter", "meters", "metre", "metres"], UnitLength.meters, "m"),
        (["cm", "centimeter", "centimeters", "centimetre", "centimetres"], UnitLength.centimeters, "cm"),
        (["mm", "millimeter", "millimeters", "millimetre", "millimetres"], UnitLength.millimeters, "mm"),
        (["mi", "mile", "miles"], UnitLength.miles, "mi"),
        (["ft", "foot", "feet"], UnitLength.feet, "ft"),
        (["in", "inch", "inches"], UnitLength.inches, "in"),
        (["yd", "yard", "yards"], UnitLength.yards, "yd"),
        (["kg", "kilogram", "kilograms", "kilo", "kilos"], UnitMass.kilograms, "kg"),
        (["g", "gram", "grams"], UnitMass.grams, "g"),
        (["lb", "lbs", "pound", "pounds"], UnitMass.pounds, "lb"),
        (["oz", "ounce", "ounces"], UnitMass.ounces, "oz"),
        (["c", "°c", "celsius"], UnitTemperature.celsius, "°C"),
        (["f", "°f", "fahrenheit"], UnitTemperature.fahrenheit, "°F"),
        (["kelvin"], UnitTemperature.kelvin, "K"),
        (["ms", "millisecond", "milliseconds"], UnitDuration.milliseconds, "ms"),
        (["s", "sec", "secs", "second", "seconds"], UnitDuration.seconds, "s"),
        (["min", "mins", "minute", "minutes"], UnitDuration.minutes, "min"),
        (["h", "hr", "hrs", "hour", "hours"], UnitDuration.hours, "h"),
        (["d", "day", "days"], day, "d"),
        (["wk", "week", "weeks"], week, "wk"),
        (["b", "byte", "bytes"], UnitInformationStorage.bytes, "B"),
        (["kb"], UnitInformationStorage.kilobytes, "KB"),
        (["mb"], UnitInformationStorage.megabytes, "MB"),
        (["gb"], UnitInformationStorage.gigabytes, "GB"),
        (["tb"], UnitInformationStorage.terabytes, "TB"),
        (["kib"], UnitInformationStorage.kibibytes, "KiB"),
        (["mib"], UnitInformationStorage.mebibytes, "MiB"),
        (["gib"], UnitInformationStorage.gibibytes, "GiB"),
    ]

    private static let byName: [String: Dimension] = {
        var map: [String: Dimension] = [:]
        for entry in table { for name in entry.names { map[name] = entry.unit } }
        return map
    }()

    static func unit(named name: String) -> Dimension? { byName[name.lowercased()] }

    static func symbol(for unit: Dimension) -> String {
        table.first { $0.unit == unit }?.symbol ?? unit.symbol
    }

    /// Nil across kinds: kilometres don't become kilograms. Kinds are
    /// compared by base unit, not class — Foundation's built-in units
    /// are a private subclass, so a custom `day` and the stock `hours`
    /// don't share a type.
    static func convert(_ value: Double, from: Dimension, to: Dimension) -> Double? {
        guard type(of: from).baseUnit() == type(of: to).baseUnit() else { return nil }
        return Measurement(value: value, unit: from).converted(to: to).value
    }
}
