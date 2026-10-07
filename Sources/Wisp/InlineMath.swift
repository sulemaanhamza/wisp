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
            // Skipping a label ("Rent:") is fine; skipping a number isn't.
            // "5 ft 10 in in cm" must never fall back to "10 in in cm" and
            // show a confident, wrong 25.4 cm.
            if start > 0, containsNumber(ns.substring(to: start)) { break }
            if let answer = evaluate(ns.substring(from: start)) { return answer }
        }
        return nil
    }

    /// Whether `text` holds a number the maths would read, as opposed to
    /// digits inside a word like `Q3`, `2nd` or `v2`.
    static func containsNumber(_ text: String) -> Bool {
        tokenize(text, lenient: true)?.contains { if case .number = $0 { return true } else { return false } } ?? false
    }

    private static let marker = try! NSRegularExpression(
        pattern: #"^\s*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+|>\s+|#{1,6}\s+)?"#
    )

    /// The text before a trailing `=`, with any list, quote or heading
    /// marker taken off. Nil unless the line really ends in a lone `=`:
    /// `==`, `<=`, `!=` and `=>` are code, not a question.
    static func expressionText(_ line: String) -> String? {
        var text = line
        // Newlines too: a note saved on Windows ends each line in CR.
        while let last = text.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(last) {
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
        /// `$12`, `40 €`: an amount that keeps its symbol through the sum.
        /// Never converted — `$5 + €5` has no answer.
        case money(Double, Currency)

        var scalar: Double? {
            switch self {
            case .number(let n): return n
            case .percent(let p): return p / 100
            case .quantity, .money: return nil
            }
        }
    }

    /// A currency symbol and where it was written, so the answer comes
    /// back the way the user writes money: `$36`, `55€`, `55 €`.
    struct Currency {
        let symbol: Character
        let suffix: Bool
        let spaced: Bool
    }

    // MARK: Tokens

    enum Token: Equatable {
        case number(Double)
        case symbol(Character)
        case word(String)
        /// Any Unicode currency sign. `spaced` is whether whitespace came
        /// before it, which only matters when it follows the number.
        case currency(Character, spaced: Bool)
    }

    private static let keywords: Set<String> = ["in", "to", "as", "of", "x"]

    /// `2k`, `1.5M` — only straight after a number, and only these
    /// spellings: lowercase `m` is metres.
    private static let multipliers: [String: Double] = ["k": 1_000, "K": 1_000, "M": 1_000_000]

    /// With `lenient`, characters the maths doesn't use are skipped
    /// instead of failing the whole text — for asking whether a label
    /// holds a number, not for calculating.
    static func tokenize(_ text: String, lenient: Bool = false) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(text)
        let n = chars.count
        func isDigit(_ i: Int) -> Bool { i < n && chars[i].isASCII && chars[i].isNumber }
        // "1,200" but not "1,2" or "1,2000": exactly three digits follow.
        func isThousandsComma(_ i: Int) -> Bool {
            chars[i] == "," && isDigit(i + 1) && isDigit(i + 2) && isDigit(i + 3) && !isDigit(i + 4)
        }
        func isLetter(_ i: Int) -> Bool { i < n && (chars[i].isLetter || chars[i] == "°") }
        func readLetters() -> String {
            var word = ""
            while isLetter(i) { word.append(chars[i]); i += 1 }
            return word
        }
        /// Skip the rest of a word that mixes letters and digits.
        func skipWord() {
            while i < n, chars[i].isLetter || chars[i].isNumber || chars[i] == "." { i += 1 }
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
                guard var value = Double(digits) else { return nil }
                // Letters glued to a number: a unit (5km), a multiplier
                // (2k), the times sign (3x4) — or part of a word (2nd,
                // 4th), in which case the whole thing is a label.
                if isLetter(i) {
                    let glued = readLetters()
                    let lower = glued.lowercased()
                    if let factor = multipliers[glued], !isDigit(i) {
                        value *= factor
                        tokens.append(.number(value))
                    } else if Units.unit(named: lower) != nil || lower == "x" {
                        tokens.append(.number(value))
                        tokens.append(.word(lower))
                    } else {
                        skipWord()
                    }
                    continue
                }
                tokens.append(.number(value))
            } else if c.isCurrencySymbol {
                let spaced = i > 0 && (chars[i - 1] == " " || chars[i - 1] == "\t")
                tokens.append(.currency(c, spaced: spaced))
                i += 1
            } else if "+-*/^()%×÷−".contains(c) {
                let normalised: Character = c == "×" ? "*" : c == "÷" ? "/" : c == "−" ? "-" : c
                tokens.append(.symbol(normalised))
                i += 1
            } else if isLetter(i) {
                let word = readLetters()
                // Q3, MP3, v2: a code, not a number.
                if isDigit(i) {
                    skipWord()
                    continue
                }
                // Words that mean something to the maths are kept; the
                // rest are labels — "4 nights × 120", "3 apples + 2" —
                // and read as if they weren't there.
                let lower = word.lowercased()
                if keywords.contains(lower) || Units.unit(named: lower) != nil {
                    tokens.append(.word(lower))
                }
            } else if lenient {
                i += 1
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
            guard var left = parseUnary() else { return nil }
            while true {
                let dividing: Bool
                if take("*") || takeWord(["x"]) { dividing = false } else if take("/") { dividing = true } else { return left }
                guard let right = parseUnary() else { return nil }
                didOperate = true
                guard let combined = Self.multiply(left, right, dividing: dividing) else { return nil }
                left = combined
            }
        }

        /// Unary minus binds looser than `^`, as in written maths:
        /// -2^2 is -4. The exponent may carry its own sign: 2^-1.
        private mutating func parseUnary() -> Value? {
            if take("-") {
                guard let value = parseUnary() else { return nil }
                switch value {
                case .number(let n): return .number(-n)
                case .percent(let p): return .percent(-p)
                case .quantity(let q, let u): return .quantity(-q, u)
                case .money(let m, let c): return .money(-m, c)
                }
            }
            if take("+") { return parseUnary() }
            return parsePower()
        }

        private mutating func parsePower() -> Value? {
            guard let base = parsePostfix() else { return nil }
            guard take("^") else { return base }
            guard let exponent = parseUnary(), let b = base.scalar, let e = exponent.scalar else { return nil }
            didOperate = true
            return .number(pow(b, e))
        }

        /// A number or group, then an optional `%` (and `of …`) or unit.
        private mutating func parsePostfix() -> Value? {
            guard let primary = parsePrimary() else { return nil }
            if take("%") {
                guard let p = primary.scalar else { return nil }
                if takeWord(["of"]) {
                    guard let whole = parseUnary() else { return nil }
                    didOperate = true
                    return Self.multiply(.number(p / 100), whole, dividing: false)
                }
                return .percent(p)
            }
            if case .number(let n) = primary, case .word(let name)? = peek, let unit = Units.unit(named: name) {
                index += 1
                // "5 ft 10 in", "1 h 30 min": a number and unit of the
                // same kind straight after adds on, as it reads.
                var total = n
                while index + 1 < tokens.count,
                      case .number(let more) = tokens[index],
                      case .word(let nextName) = tokens[index + 1],
                      let nextUnit = Units.unit(named: nextName),
                      let converted = Units.convert(more, from: nextUnit, to: unit) {
                    total += converted
                    index += 2
                    didOperate = true
                }
                return .quantity(total, unit)
            }
            // 40€, 40 €
            if case .number(let n) = primary, case .currency(let symbol, let spaced)? = peek {
                index += 1
                return .money(n, Currency(symbol: symbol, suffix: true, spaced: spaced))
            }
            return primary
        }

        private mutating func parsePrimary() -> Value? {
            // $12, € 40
            if case .currency(let symbol, _)? = peek {
                index += 1
                guard case .number(let n)? = peek else { return nil }
                index += 1
                return .money(n, Currency(symbol: symbol, suffix: false, spaced: false))
            }
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
            case (.money(let x, let c), .money(let y, let d)):
                return c.symbol == d.symbol ? .money(x + sign * y, c) : nil
            // $14 + 18% is the bill with the tip on top.
            case (.money(let x, let c), .percent(let p)):
                return .money(x * (1 + sign * p / 100), c)
            // A bare number beside money is more of the same money:
            // "$40 + 15 tip".
            case (.money(let x, let c), .number(let y)):
                return .money(x + sign * y, c)
            case (.number(let x), .money(let y, let c)):
                return .money(x + sign * y, c)
            case (.money, _), (_, .money):
                return nil
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
            // 15% + 150 has no reading worth guessing at.
            case (.percent, .number), (.percent, .quantity):
                return nil
            default:
                guard let x = a.scalar, let y = b.scalar else { return nil }
                return .number(x + sign * y)
            }
        }

        static func multiply(_ a: Value, _ b: Value, dividing: Bool) -> Value? {
            switch (a, b) {
            // $100 / $25 is a plain ratio; $ × $ means nothing.
            case (.money(let x, let c), .money(let y, let d)):
                guard dividing, c.symbol == d.symbol, y != 0 else { return nil }
                return .number(x / y)
            case (.money(let x, let c), _):
                guard let y = b.scalar else { return nil }
                if dividing { return y == 0 ? nil : .money(x / y, c) }
                return .money(x * y, c)
            case (_, .money(let y, let c)):
                guard !dividing, let x = a.scalar else { return nil }
                return .money(x * y, c)
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
        case .money(let m, let currency):
            return formatMoney(m, currency)
        }
    }

    /// Whole amounts without decimals, anything else to the cent:
    /// $36, $37.50 — never $37.5. The sign leads, as in -$3.
    static func formatMoney(_ m: Double, _ currency: Currency) -> String? {
        guard m.isFinite else { return nil }
        let cents = (m * 100).rounded()
        let whole = cents.truncatingRemainder(dividingBy: 100) == 0
        let key = whole ? -10 : -12
        let formatter = formatters[key] ?? {
            let f = NumberFormatter()
            f.locale = Locale(identifier: "en_US")
            f.numberStyle = .decimal
            f.usesGroupingSeparator = true
            f.minimumFractionDigits = whole ? 0 : 2
            f.maximumFractionDigits = whole ? 0 : 2
            formatters[key] = f
            return f
        }()
        guard let digits = formatter.string(from: NSNumber(value: abs(cents) / 100)) else { return nil }
        let sign = cents < 0 ? "-" : ""
        let symbol = String(currency.symbol)
        return currency.suffix
            ? sign + digits + (currency.spaced ? " " : "") + symbol
            : sign + symbol + digits
    }

    static func formatNumber(_ n: Double, maxFraction: Int) -> String? {
        guard n.isFinite else { return nil }
        // Fixed decimals suit everyday sizes. Something too small for
        // them would round to a flat "0", and something huge shows the
        // float's noise, so both switch to significant digits.
        let tiny = n != 0 && abs(n) < 0.5 * pow(10, -Double(maxFraction))
        let huge = abs(n) >= 1e15
        let key = tiny ? -1 : huge ? -2 : maxFraction
        let formatter = formatters[key] ?? {
            let f = NumberFormatter()
            // Always "1,234.5": the same notation the parser reads back.
            f.locale = Locale(identifier: "en_US")
            f.numberStyle = .decimal
            f.usesGroupingSeparator = true
            if tiny || huge {
                f.usesSignificantDigits = true
                f.maximumSignificantDigits = tiny ? 4 : 15
            } else {
                f.minimumFractionDigits = 0
                f.maximumFractionDigits = maxFraction
            }
            formatters[key] = f
            return f
        }()
        let text = formatter.string(from: NSNumber(value: n))
        return text == "-0" ? "0" : text
    }

    /// NumberFormatter is slow to make and safe to reuse on one thread;
    /// this enum is main-actor, so one per style is enough.
    private static var formatters: [Int: NumberFormatter] = [:]

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
