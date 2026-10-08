import Foundation

/// Inline reminders: a line that starts with "Remind me" names a time,
/// and at that time a notification brings you back to the line.
///
/// This file is the pure half — which lines count, what time a line
/// asks for, and how that time is shown in grey. ReminderStore keeps
/// the reminders that were set and schedules them.
///
/// Times are read in two parts. macOS's date reader (NSDataDetector)
/// handles dates and clock times, but a spike showed it misses
/// durations ("in 10 minutes"), "next week" and a bare "at 7", and
/// reads a day with no time as noon. Those Wisp reads itself.
@MainActor
enum Reminders {
    /// What a reminder line asks for.
    enum Reading: Equatable {
        /// A time Wisp understood, still ahead.
        case at(Date)
        /// A time that has already gone: yesterday, last Friday.
        case past
        /// A "Remind me" line with no time in it.
        case noTime
    }

    /// A day named without a time fires at this hour.
    static let defaultHour = 9

    // MARK: Which lines count

    private static let marker = try! NSRegularExpression(
        pattern: #"^\s*(?:[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+|>\s+)?"#
    )

    /// The words after "Remind me", or nil when the line isn't a
    /// reminder. The phrase has to open the line — after a bullet,
    /// number, checkbox or quote — so "I told him to remind me
    /// tomorrow" isn't one. A ticked task is done, so it isn't either.
    static func body(ofLine line: String) -> String? {
        guard !Checkbox.isChecked(line) else { return nil }
        let text = sentence(ofLine: line)
        guard text.lowercased().hasPrefix("remind me") else { return nil }
        var rest = text.dropFirst("remind me".count)
        if rest.first == ":" {
            // "Remind me: tomorrow …" reads the same as without the colon.
            rest = rest.dropFirst()
        } else if !(rest.isEmpty || rest.first == " " || rest.first == "\t") {
            return nil  // "remind meeting"
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    static func isReminder(_ line: String) -> Bool { body(ofLine: line) != nil }

    /// The line without its list, checkbox or quote marker — what a
    /// notification shows.
    static func sentence(ofLine line: String) -> String {
        let ns = line as NSString
        let start = marker.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
            .map { NSMaxRange($0.range) } ?? 0
        return ns.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Reading the time

    private static let durationPattern = try! NSRegularExpression(
        pattern: #"\bin\s+(half\s+an|an?|\d+(?:\.\d+)?)\s*(minutes?|mins?|hours?|hrs?|h|days?|weeks?)\b"#,
        options: .caseInsensitive
    )
    private static let nextWeekPattern = try! NSRegularExpression(pattern: #"\bnext\s+week\b"#, options: .caseInsensitive)
    private static let weekendPattern = try! NSRegularExpression(
        pattern: #"\b(?:this|the|on\s+the|at\s+the)\s+weekend\b"#, options: .caseInsensitive
    )
    private static let endOfDayPattern = try! NSRegularExpression(
        pattern: #"\b(?:(?:by\s+)?(?:the\s+)?end\s+of\s+(?:the\s+)?day|eod)\b"#, options: .caseInsensitive
    )
    private static let morningPattern = try! NSRegularExpression(pattern: #"\bin\s+the\s+morning\b"#, options: .caseInsensitive)
    /// End of day means 5 PM.
    static let endOfDayHour = 17
    /// "at 7": an hour with no minutes, no am/pm, no colon after it.
    private static let bareHourPattern = try! NSRegularExpression(
        pattern: #"\bat\s+(\d{1,2})\b(?!\s*(?::|\.\d|am\b|pm\b|a\.m|p\.m|o'clock))"#,
        options: .caseInsensitive
    )
    /// Words that carry a time of day, so the reader's own time stands.
    /// "at 7" counts: in "tomorrow at 7" the hour belongs to tomorrow,
    /// not to the bare-hour rule, which would put it at 7 PM today.
    private static let timeWords = try! NSRegularExpression(
        pattern: #"\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.?|p\.m\.?)\b|\d{1,2}:\d{2}|\bat\s+\d{1,2}\b|\b(?:noon|midnight|tonight|evening|morning|afternoon|night)\b"#,
        options: .caseInsensitive
    )
    /// A phrase that is only a clock time — "3pm", "at 15:00", "noon".
    private static let timeOnly = try! NSRegularExpression(
        pattern: #"^\s*(?:at\s+)?(?:\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.?|p\.m\.?)?|noon|midnight)\s*$"#,
        options: .caseInsensitive
    )
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// What `line` asks for, and the words that named the time — the
    /// phrase an edited line is matched by. Nil when the line isn't a
    /// reminder at all.
    ///
    /// `now` places durations, bare hours and "next week". Dates and
    /// clock times come from macOS's reader, which always works from
    /// the real clock.
    static func read(_ line: String, now: Date = Date(), calendar: Calendar = .current) -> (reading: Reading, phrase: String)? {
        guard let body = body(ofLine: line) else { return nil }
        let ns = body as NSString
        let all = NSRange(location: 0, length: ns.length)

        if let m = durationPattern.firstMatch(in: body, range: all) {
            let phrase = ns.substring(with: m.range)
            let count = ns.substring(with: m.range(at: 1)).lowercased()
            let unit = ns.substring(with: m.range(at: 2)).lowercased()
            let amount = count.hasPrefix("half") ? 0.5 : (count == "a" || count == "an") ? 1 : Double(count) ?? 0
            switch unit.first {
            case "m":
                return (.at(now.addingTimeInterval(amount * 60)), phrase)
            case "h":
                return (.at(now.addingTimeInterval(amount * 3600)), phrase)
            default:
                // Days and weeks name a day: it fires at the time given
                // with it, or the default hour.
                let days = Int((unit.first == "w" ? amount * 7 : amount).rounded())
                guard let day = calendar.date(byAdding: .day, value: days, to: now) else { return (.noTime, phrase) }
                return (.at(at(clockTime(in: body), on: day, calendar: calendar)), phrase)
            }
        }

        if let m = nextWeekPattern.firstMatch(in: body, range: all) {
            // Next week is the coming Monday.
            var monday = calendar.startOfDay(for: now)
            repeat { monday = calendar.date(byAdding: .day, value: 1, to: monday)! }
            while calendar.component(.weekday, from: monday) != 2
            return (.at(at(clockTime(in: body), on: monday, calendar: calendar)), ns.substring(with: m.range))
        }

        if let m = weekendPattern.firstMatch(in: body, range: all) {
            // The first Saturday or Sunday still ahead, at the time given
            // or the default hour: Saturday morning, or Sunday if
            // Saturday's has gone.
            let time = clockTime(in: body)
            for offset in 0...8 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
                let weekday = calendar.component(.weekday, from: day)
                guard weekday == 7 || weekday == 1 else { continue }
                let date = at(time, on: day, calendar: calendar)
                if date > now { return (.at(date), ns.substring(with: m.range)) }
            }
        }

        if let m = endOfDayPattern.firstMatch(in: body, range: all) {
            // 5 PM today, or tomorrow's once today's has gone.
            var date = at((endOfDayHour, 0), on: now, calendar: calendar)
            if date <= now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
            return (.at(date), ns.substring(with: m.range))
        }

        if let m = bareHourPattern.firstMatch(in: body, range: all),
           let hour = Int(ns.substring(with: m.range(at: 1))), hour <= 23,
           detector.firstMatch(in: body, range: all).map({ !hasTimeWords(ns.substring(with: $0.range)) }) ?? true {
            return (.at(nextOccurrence(ofHour: hour, after: now, calendar: calendar)), ns.substring(with: m.range))
        }

        guard let match = detector.firstMatch(in: body, range: all), var date = match.date else {
            // "in the morning", with no day named: the next 9 AM. With a
            // day ("Friday in the morning"), macOS's reading above wins.
            if let m = morningPattern.firstMatch(in: body, range: all) {
                var next = at(nil, on: now, calendar: calendar)
                if next <= now { next = calendar.date(byAdding: .day, value: 1, to: next) ?? next }
                return (.at(next), ns.substring(with: m.range))
            }
            return (.noTime, "")
        }
        let phrase = ns.substring(with: match.range)
        if !hasTimeWords(phrase) {
            // The reader puts a bare day at noon.
            date = at(nil, on: date, calendar: calendar)
        }
        if date <= now {
            // A clock time that has gone today means tomorrow; a day
            // or date that has gone is simply past.
            guard isTimeOnly(phrase), let next = calendar.date(byAdding: .day, value: 1, to: date) else {
                return (.past, phrase)
            }
            date = next
        }
        return (.at(date), phrase)
    }

    private static func hasTimeWords(_ text: String) -> Bool {
        timeWords.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func isTimeOnly(_ text: String) -> Bool {
        timeOnly.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// The hour and minute of a clock time elsewhere in the line, as
    /// macOS reads it, for "in 3 days at 5pm".
    private static func clockTime(in body: String) -> (hour: Int, minute: Int)? {
        let ns = body as NSString
        guard let match = detector.firstMatch(in: body, range: NSRange(location: 0, length: ns.length)),
              let date = match.date, hasTimeWords(ns.substring(with: match.range)) else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? defaultHour, parts.minute ?? 0)
    }

    private static func at(_ time: (hour: Int, minute: Int)?, on day: Date, calendar: Calendar) -> Date {
        calendar.date(
            bySettingHour: time?.hour ?? defaultHour, minute: time?.minute ?? 0, second: 0, of: day
        ) ?? day
    }

    /// "at 7" means the next time the clock shows 7 — 7 PM if it's
    /// already past 7 AM. A 24-hour figure ("at 19") is taken as said.
    static func nextOccurrence(ofHour hour: Int, after now: Date, calendar: Calendar) -> Date {
        let hours = hour > 12 ? [hour] : hour == 12 ? [12, 0] : [hour, hour + 12]
        var candidates: [Date] = []
        for offset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            for h in hours {
                if let d = calendar.date(bySettingHour: h, minute: 0, second: 0, of: day), d > now {
                    candidates.append(d)
                }
            }
        }
        return candidates.min() ?? now.addingTimeInterval(3600)
    }

    // MARK: Showing a time

    /// What the grey text after a reminder line says.
    enum Label: Equatable {
        /// Read as you type, or set: the time it will fire.
        case due(Date)
        case sent(Date)
        case past
        case noTime
        case notificationsOff
        /// Its time came while notifications weren't allowed.
        case notSent
        case outsideApplications
        case notOnThisMac

        func text(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
            switch self {
            case .due(let date): return "\u{2192} " + Reminders.describe(date, now: now, calendar: calendar, locale: locale)
            case .sent(let date): return "sent " + Reminders.describe(date, now: now, calendar: calendar, locale: locale)
            case .past: return "time has passed"
            case .noTime: return "no time found"
            case .notificationsOff: return "notifications are off"
            case .notSent: return "not sent: notifications were off"
            case .outsideApplications: return "move Wisp to Applications to get reminders"
            case .notOnThisMac: return "not set on this Mac"
            }
        }
    }

    /// "2:42 PM" today, "Tomorrow 9:00 AM", "Fri 9:00 AM" this week,
    /// "14 Oct 10:00 AM" further out — with the year when it differs.
    /// The clock follows the Mac's 12- or 24-hour setting.
    nonisolated static func describe(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let time = DateFormatter()
        time.locale = locale
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        let clock = time.string(from: date)
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if days == 0 { return clock }
        if days == 1 { return "Tomorrow \(clock)" }
        if days == -1 { return "Yesterday \(clock)" }
        let dayFormat = DateFormatter()
        dayFormat.locale = locale
        dayFormat.calendar = calendar
        dayFormat.timeZone = calendar.timeZone
        if days > 1 && days < 7 {
            dayFormat.setLocalizedDateFormatFromTemplate("EEE")
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            dayFormat.setLocalizedDateFormatFromTemplate("dMMM")
        } else {
            dayFormat.setLocalizedDateFormatFromTemplate("dMMMyyyy")
        }
        return "\(dayFormat.string(from: date)) \(clock)"
    }
}
