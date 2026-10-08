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

    /// The line ticked off, as the notification's Done button leaves it:
    /// a task's box checked, anything else made a checked task the way
    /// ⌘L would, its indent and bullet kept.
    static func ticked(_ line: String) -> String {
        guard !Checkbox.isChecked(line) else { return line }
        let task = Checkbox.boxRange(in: line) == nil ? LineEditing.toggleTask(line: line) : line
        return Checkbox.toggling(task) ?? line
    }

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
        pattern: #"\bat\s+(\d{1,2})\b(?!\s*(?::|\.\d|am\b|pm\b|a\.m|p\.m|o['’]?clock))"#,
        options: .caseInsensitive
    )
    /// Words that carry a time of day, so the reader's own time stands.
    private static let timeWords = try! NSRegularExpression(
        pattern: #"\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.?|p\.m\.?|o['’]?clock)\b|\d{1,2}:\d{2}|\bat\s+\d{1,2}\b|\b(?:noon|midnight|tonight|evening|morning|afternoon|night)\b"#,
        options: .caseInsensitive
    )
    /// A phrase that is only a clock time — "3pm", "at 15:00", "noon".
    private static let timeOnly = try! NSRegularExpression(
        pattern: #"^\s*(?:at\s+)?(?:\d{1,2}(?::\d{2})?\s*(?:am|pm|a\.m\.?|p\.m\.?|o['’]?clock)?|noon|midnight)\s*$"#,
        options: .caseInsensitive
    )
    private static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let weekdayPattern = try! NSRegularExpression(
        pattern: #"\b(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#, options: .caseInsensitive
    )
    private static let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    /// Past this, a duration is a typo or a joke, not a reminder — and
    /// converting it would overflow.
    private static let longestDuration: Double = 100 * 366 * 86_400

    /// One piece of a line that says something about when.
    private struct Part {
        let range: NSRange
        let phrase: String
    }

    /// What `line` asks for, and the words that named the time — what
    /// an edit is compared by. Nil when the line isn't a reminder.
    ///
    /// A line is read as a whole: the first thing that names a day (or
    /// a span, "in 2 hours") is the anchor, and a time of day written
    /// anywhere else in the line attaches to it — "tomorrow to call
    /// John at 3pm", "Friday by end of day". With no day, a time of day
    /// alone means today, or tomorrow once it has gone.
    ///
    /// `now` places what Wisp reads itself. Dates and clock times come
    /// from macOS's reader, which always works from the real clock.
    static func read(_ line: String, now: Date = Date(), calendar: Calendar = .current) -> (reading: Reading, phrase: String)? {
        guard let body = body(ofLine: line) else { return nil }
        let ns = body as NSString
        let all = NSRange(location: 0, length: ns.length)
        func part(_ m: NSTextCheckingResult?) -> Part? {
            m.map { Part(range: $0.range, phrase: ns.substring(with: $0.range)) }
        }

        let duration = durationPattern.firstMatch(in: body, range: all)
        let nextWeek = part(nextWeekPattern.firstMatch(in: body, range: all))
        let weekend = part(weekendPattern.firstMatch(in: body, range: all))
        let endOfDay = part(endOfDayPattern.firstMatch(in: body, range: all))
        let morning = part(morningPattern.firstMatch(in: body, range: all))
        let bareHour = bareHourPattern.firstMatch(in: body, range: all)
        let ours = [duration?.range, nextWeek?.range, weekend?.range, endOfDay?.range, morning?.range].compactMap { $0 }
        // macOS's matches, minus anything Wisp reads itself ("in 3 days"
        // is a duration here, not one of its dates).
        let found = detector.matches(in: body, range: all).filter { m in
            m.date != nil && !ours.contains { NSIntersectionRange($0, m.range).length > 0 }
        }
        let clockMatches = found.filter { isTimeOnly(ns.substring(with: $0.range)) }
        let dayMatches = found.filter { !isTimeOnly(ns.substring(with: $0.range)) }

        // "in 10 minutes", "in 2 hours": a span from now, whatever else
        // the line says — if it comes first.
        let firstDay = dayMatches.map(\.range.location).min() ?? .max
        let firstNamedDay = min(firstDay, nextWeek?.range.location ?? .max, weekend?.range.location ?? .max)
        if let duration, duration.range.location < firstNamedDay {
            let phrase = ns.substring(with: duration.range)
            let count = ns.substring(with: duration.range(at: 1)).lowercased()
            let unit = ns.substring(with: duration.range(at: 2)).lowercased()
            let amount = count.hasPrefix("half") ? 0.5 : (count == "a" || count == "an") ? 1 : Double(count) ?? 0
            let seconds = amount * (unit.first == "m" ? 60 : unit.first == "h" ? 3600 : unit.first == "w" ? 7 * 86_400 : 86_400)
            guard seconds.isFinite, seconds > 0, seconds <= longestDuration else { return (.noTime, phrase) }
            if unit.first == "m" || unit.first == "h" {
                return (.at(now.addingTimeInterval(seconds)), phrase)
            }
            // Days and weeks name a day: it fires at the time given with
            // it, or the default hour.
            let day = calendar.date(byAdding: .day, value: Int(seconds / 86_400), to: now) ?? now
            return finish(on: day, anchor: Part(range: duration.range, phrase: phrase), body: ns, now: now, calendar: calendar,
                          clocks: clockMatches, endOfDay: endOfDay, morning: morning, bareHour: bareHour)
        }

        // "next week", or "Wednesday next week": that week's Monday, or
        // the named day in it.
        // macOS reads "Wednesday next week" as one phrase overlapping
        // Wisp's own, so the weekday is looked for directly.
        let weekday = weekdayPattern.firstMatch(in: body, range: all)
        if let nextWeek, nextWeek.range.location <= firstDay || weekday != nil {
            var monday = calendar.startOfDay(for: now)
            repeat { monday = calendar.date(byAdding: .day, value: 1, to: monday)! }
            while calendar.component(.weekday, from: monday) != 2
            var day = monday
            var anchor = nextWeek
            if let weekday, let index = weekdayNames.firstIndex(of: ns.substring(with: weekday.range).lowercased()) {
                // Monday-based: Monday is 0 days on, Sunday 6.
                day = calendar.date(byAdding: .day, value: (index + 6) % 7, to: monday) ?? monday
                anchor = Part(
                    range: NSUnionRange(weekday.range, nextWeek.range),
                    phrase: ns.substring(with: weekday.range) + " " + nextWeek.phrase
                )
            }
            return finish(on: day, anchor: anchor, body: ns, now: now, calendar: calendar,
                          clocks: clockMatches, endOfDay: endOfDay, morning: morning, bareHour: bareHour)
        }

        // "this weekend": the first Saturday or Sunday still ahead, at the
        // time given or the default hour.
        if let weekend, weekend.range.location <= firstDay {
            for offset in 0...8 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
                let weekday = calendar.component(.weekday, from: day)
                guard weekday == 7 || weekday == 1 else { continue }
                let result = finish(on: day, anchor: weekend, body: ns, now: now, calendar: calendar,
                                    clocks: clockMatches, endOfDay: endOfDay, morning: morning, bareHour: bareHour)
                if case .at = result.reading { return result }
            }
        }

        // A day from macOS's reader: "tomorrow", "Friday at 3pm", "Dec 25".
        if let dayMatch = dayMatches.first, let date = dayMatch.date {
            let anchor = Part(range: dayMatch.range, phrase: ns.substring(with: dayMatch.range))
            if hasTimeWords(anchor.phrase) {
                // Its own time: "tomorrow at 7am", "tonight".
                return date > now ? (.at(date), anchor.phrase) : (.past, anchor.phrase)
            }
            return finish(on: date, anchor: anchor, body: ns, now: now, calendar: calendar,
                          clocks: clockMatches, endOfDay: endOfDay, morning: morning, bareHour: bareHour)
        }

        // No day: a time of day alone. Today, or tomorrow once it's gone.
        let times: [(location: Int, phrase: String, date: Date)] = [
            clockMatches.first.flatMap { m in m.date.map { (m.range.location, ns.substring(with: m.range), $0) } },
            endOfDay.map { ($0.range.location, $0.phrase, at((endOfDayHour, 0), on: now, calendar: calendar)) },
            morning.map { ($0.range.location, $0.phrase, at(nil, on: now, calendar: calendar)) },
            bareHour.flatMap { m in
                Int(ns.substring(with: m.range(at: 1))).flatMap { $0 <= 23 ? $0 : nil }
                    .map { (m.range.location, ns.substring(with: m.range), nextOccurrence(ofHour: $0, after: now, calendar: calendar)) }
            },
        ].compactMap { $0 }
        guard let time = times.min(by: { $0.location < $1.location }) else { return (.noTime, "") }
        var date = time.date
        if date <= now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
        return (.at(date), time.phrase)
    }

    /// A named day, at the time of day the line gives elsewhere — the
    /// first of a clock time, "end of day", "in the morning" or a bare
    /// hour — or the default hour. A day already gone is past.
    private static func finish(
        on day: Date, anchor: Part, body ns: NSString, now: Date, calendar: Calendar,
        clocks: [NSTextCheckingResult], endOfDay: Part?, morning: Part?, bareHour: NSTextCheckingResult?
    ) -> (reading: Reading, phrase: String) {
        var candidates: [(location: Int, phrase: String, time: (hour: Int, minute: Int))] = []
        if let clock = clocks.first, let date = clock.date {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            candidates.append((clock.range.location, ns.substring(with: clock.range), (parts.hour ?? defaultHour, parts.minute ?? 0)))
        }
        if let endOfDay { candidates.append((endOfDay.range.location, endOfDay.phrase, (endOfDayHour, 0))) }
        if let morning { candidates.append((morning.range.location, morning.phrase, (defaultHour, 0))) }
        if let bareHour, let hour = Int(ns.substring(with: bareHour.range(at: 1))), hour <= 23 {
            candidates.append((bareHour.range.location, ns.substring(with: bareHour.range), (hourOnNamedDay(hour, anchor: anchor.phrase), 0)))
        }
        let time = candidates.min(by: { $0.location < $1.location })
        let date = at(time?.time, on: day, calendar: calendar)
        let phrase = time.map { "\(anchor.phrase) \($0.phrase)" } ?? anchor.phrase
        return date > now ? (.at(date), phrase) : (.past, phrase)
    }

    /// "Tomorrow … at 7": which 7 macOS would mean, by asking it about
    /// "tomorrow at 7" — so a time split from its day reads the same as
    /// one written next to it. Failing that, 1–6 are afternoon hours.
    private static func hourOnNamedDay(_ hour: Int, anchor: String) -> Int {
        guard hour <= 12 else { return hour }
        let joined = "\(anchor) at \(hour)"
        if let date = detector.firstMatch(in: joined, range: NSRange(location: 0, length: (joined as NSString).length))?.date {
            return Calendar.current.component(.hour, from: date)
        }
        return hour < 7 ? hour + 12 : hour
    }

    private static func hasTimeWords(_ text: String) -> Bool {
        timeWords.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func isTimeOnly(_ text: String) -> Bool {
        timeOnly.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
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
        /// Read as you type: the time it would fire. Not set yet.
        case due(Date)
        /// Set — handed to macOS, or about to be. Drawn with a bell in
        /// place of the arrow, so a finished line looks different from
        /// one still being written.
        case set(Date)
        case sent(Date)
        case past
        case noTime
        case notificationsOff
        /// Set, but macOS hasn't been asked yet, or the prompt went
        /// unanswered; it comes back on the next panel open.
        case needsPermission
        /// Its time came while it couldn't be handed to macOS.
        case notSent
        case outsideApplications
        case notOnThisMac

        @MainActor
        func text(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
            switch self {
            case .due(let date): return "\u{2192} " + Reminders.describe(date, now: now, calendar: calendar, locale: locale)
            case .set(let date): return Reminders.describe(date, now: now, calendar: calendar, locale: locale)
            case .sent(let date): return "sent " + Reminders.describe(date, now: now, calendar: calendar, locale: locale)
            case .past: return "time has passed"
            case .noTime: return "no time found"
            case .notificationsOff: return "notifications are off"
            case .needsPermission: return "allow notifications to get this"
            case .notSent: return "not sent: notifications were off"
            case .outsideApplications: return "move Wisp to Applications to get reminders"
            case .notOnThisMac: return "not set on this Mac"
            }
        }

        /// For when the full text won't fit beside a long line: the
        /// clock time alone, or the gist.
        @MainActor
        func shortText(now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
            switch self {
            case .due(let date): return "\u{2192} " + Reminders.clock(date, calendar: calendar, locale: locale)
            case .set(let date): return Reminders.clock(date, calendar: calendar, locale: locale)
            case .sent: return "sent"
            case .past: return "passed"
            case .noTime: return "no time"
            case .notificationsOff: return "notifications off"
            case .needsPermission: return "needs permission"
            case .notSent: return "not sent"
            case .outsideApplications: return "move to Applications"
            case .notOnThisMac: return "not set here"
            }
        }

        /// The SF Symbol drawn before the text, if any: a bell while it
        /// waits to fire, a tick once it has — click it when it's done.
        var symbol: String? {
            switch self {
            case .set: return "bell"
            case .sent: return "checkmark.circle"
            default: return nil
            }
        }

        /// Clicking the symbol ticks the line off.
        var ticksLine: Bool {
            if case .sent = self { return true }
            return false
        }
    }

    /// "2:42 PM" today, "Tomorrow 9:00 AM", "Fri 9:00 AM" this week,
    /// "14 Oct 10:00 AM" further out — with the year when it differs.
    /// The clock follows the Mac's 12- or 24-hour setting.
    static func clock(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        formatter(nil, calendar: calendar, locale: locale).string(from: date)
    }

    static func describe(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let clock = clock(date, calendar: calendar, locale: locale)
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if days == 0 { return clock }
        if days == 1 { return "Tomorrow \(clock)" }
        if days == -1 { return "Yesterday \(clock)" }
        let template = days > 1 && days < 7 ? "EEE"
            : calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "dMMM" : "dMMMyyyy"
        return "\(formatter(template, calendar: calendar, locale: locale).string(from: date)) \(clock)"
    }

    /// DateFormatters are slow to make, and a large note can have
    /// hundreds of reminder lines restyled at once; one per style is kept.
    /// `template` nil is the short clock time.
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ template: String?, calendar: Calendar, locale: Locale) -> DateFormatter {
        let key = "\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)|\(template ?? "time")"
        if let cached = formatters[key] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        if let template {
            f.setLocalizedDateFormatFromTemplate(template)
        } else {
            f.dateStyle = .none
            f.timeStyle = .short
        }
        formatters[key] = f
        return f
    }
}
