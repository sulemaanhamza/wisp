import Foundation
import UserNotifications

/// One reminder that was set. Kept on this Mac only.
struct Reminder: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        /// Handed to macOS.
        case scheduled
        /// Set, but not with macOS: notifications aren't allowed, Wisp
        /// isn't in an Applications folder, macOS already holds as many as
        /// it will — or its time has gone.
        case waiting
        case cancelled
    }

    var id: String
    /// The line as written. A reminder is found again by its line.
    var line: String
    /// The words that named the time. An edited line that keeps them
    /// keeps its reminder, and its time.
    var phrase: String
    var fireDate: Date
    var state: State
    /// macOS holds it — and if its time has gone, held it then: it was
    /// sent. Cleared when it's taken back before its time.
    var handedOver = false
    /// Filed to the Inbox with its note: it still fires, though its
    /// line is no longer in the note.
    var archived = false
    var cancelledAt: Date?

    init(id: String, line: String, phrase: String, fireDate: Date, state: State) {
        self.id = id
        self.line = line
        self.phrase = phrase
        self.fireDate = fireDate
        self.state = state
    }

    /// Fields added later decode with their defaults, so an older
    /// Reminders.json still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        line = try c.decode(String.self, forKey: .line)
        phrase = try c.decode(String.self, forKey: .phrase)
        fireDate = try c.decode(Date.self, forKey: .fireDate)
        state = try c.decode(State.self, forKey: .state)
        handedOver = try c.decodeIfPresent(Bool.self, forKey: .handedOver) ?? false
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        cancelledAt = try c.decodeIfPresent(Date.self, forKey: .cancelledAt)
    }
}

enum ReminderPermission: Sendable, Equatable {
    case allowed, denied, notDetermined
}

/// The macOS side, behind a protocol so the store's decisions can be
/// tested without posting real notifications.
@MainActor
protocol ReminderScheduling: AnyObject {
    /// macOS refuses notifications to an app outside an Applications
    /// folder, without asking (seen in the spike).
    var canDeliver: Bool { get }
    /// `done(false)`: macOS didn't take it.
    func schedule(_ reminder: Reminder, done: @escaping @Sendable @MainActor (Bool) -> Void)
    func cancel(_ ids: [String])
    /// The ids macOS holds, still to fire.
    func pending(_ done: @escaping @Sendable @MainActor ([String]) -> Void)
    func currentPermission(_ done: @escaping @Sendable @MainActor (ReminderPermission) -> Void)
    func requestPermission(_ done: @escaping @Sendable @MainActor (Bool) -> Void)
    /// Wait, briefly, for hand-offs still in flight — called as Wisp quits.
    func flush(timeout: TimeInterval)
}

/// Every reminder that was set, and the rules for keeping them in step
/// with the note.
///
/// Only typing sets a reminder (`commit`, called when a line is
/// finished). A note loaded from disk never does — otherwise every Mac
/// sharing an iCloud note would set the same reminder, and updating to
/// this version would suddenly schedule old "Remind me" lines.
@MainActor
final class ReminderStore {
    static let didChange = Notification.Name("WispRemindersDidChange")

    static let shared = ReminderStore(
        fileURL: StorageLocation.defaultFolder.appendingPathComponent("Reminders.json"),
        scheduler: SystemReminderScheduler()
    )

    /// A line cancelled this recently and back again — cut and pasted,
    /// undone, unticked — is the same reminder.
    private static let reviveWindow: TimeInterval = 10 * 60
    /// How long a cancelled or filed reminder is kept once it can't
    /// matter: well past the revive window.
    private static let historyKept: TimeInterval = 86_400
    /// macOS keeps 100 pending notifications an app and silently drops
    /// the rest (measured on macOS 26); 64 is iOS's documented limit and
    /// leaves room should an older macOS keep fewer. The soonest are
    /// handed over, and the rest as those fire.
    static let pendingLimit = 64

    let fileURL: URL
    let scheduler: ReminderScheduling
    /// The time when an answer arrives — a permission prompt answered
    /// minutes after it was asked. The self-tests move it on.
    private let clock: () -> Date
    private(set) var reminders: [Reminder] = []
    private(set) var permission: ReminderPermission = .notDetermined
    /// Lines being edited: each draft, and the set line it came from. A
    /// save mid-edit doesn't cancel that reminder, and the draft shows it.
    var editing: [String: String] = [:]
    /// Reminder lines that arrived from disk with nothing set for them.
    private var externalLines: Set<String> = []
    /// Reminders.json held entries this version couldn't read, so a
    /// notification macOS holds may belong to one: leave those be.
    private var loadedCleanly = true
    private var asking = false
    /// `sync` waits for macOS to say what's allowed: at launch the note
    /// loads before it answers, and treating "not asked yet" as "off"
    /// would take every reminder back only to hand it over again.
    private var permissionChecked = false
    private var changePosted = false
    /// Readings of lines with nothing set, for the current minute. A
    /// redraw asks about every visible reminder line, and reading the time
    /// is the costly part. Labels show minutes, so reusing a reading
    /// within one can't show a wrong time.
    private var readings: [String: (reading: Reminders.Reading, phrase: String)?] = [:]
    private var readingsMinute = 0
    /// Fires when the next reminder is due, so its line turns to "sent"
    /// while the panel is open — macOS only tells a running app that's in
    /// front — and the next waiting one is handed over.
    private var tick: Timer?

    init(fileURL: URL, scheduler: ReminderScheduling, clock: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.scheduler = scheduler
        self.clock = clock
        load()
        scheduleTick()
    }

    /// The Mac woke, or its clock or time zone changed. The tick runs on
    /// uptime, which stops during sleep, and a changed clock moves every
    /// time: work them out again.
    func timeChanged() {
        sync()
        scheduleTick()
        changed()
    }

    // MARK: What a line shows

    /// The grey text after `line`, or nil when it isn't a reminder.
    func label(forLine line: String, now: Date = Date()) -> Reminders.Label? {
        guard Reminders.isReminder(line) else { return nil }
        if let reminder = active(line) { return label(for: reminder, now: now) }
        guard let read = reading(line, now: now) else { return nil }
        // Being edited from a set line, with its time words unchanged: it
        // will keep that reminder, so it shows it.
        if let origin = editing[line], let reminder = active(origin),
           reminder.phrase.lowercased() == read.phrase.lowercased() {
            return label(for: reminder, now: now)
        }
        switch read.reading {
        case .past: return .past
        case .noTime: return .noTime
        case .at(let date):
            if externalLines.contains(line) { return .notOnThisMac }
            if !scheduler.canDeliver { return .outsideApplications }
            if permission == .denied { return .notificationsOff }
            return .due(date)
        }
    }

    private func label(for reminder: Reminder, now: Date) -> Reminders.Label {
        if reminder.fireDate <= now {
            return reminder.handedOver ? .sent(reminder.fireDate) : .notSent
        }
        if reminder.state == .scheduled {
            // Turned off since it was set: macOS won't show it.
            return permission == .denied ? .notificationsOff : .set(reminder.fireDate)
        }
        if !scheduler.canDeliver { return .outsideApplications }
        switch permission {
        case .denied: return .notificationsOff
        case .notDetermined: return .needsPermission
        // Waiting its turn behind the soonest ones macOS holds.
        case .allowed: return .set(reminder.fireDate)
        }
    }

    private func reading(_ line: String, now: Date) -> (reading: Reminders.Reading, phrase: String)? {
        let minute = Int((now.timeIntervalSinceReferenceDate / 60).rounded(.down))
        if minute != readingsMinute {
            readings = [:]
            readingsMinute = minute
        }
        if let known = readings[line] { return known }
        let read = Reminders.read(line, now: now)
        readings.updateValue(read, forKey: line)
        return read
    }

    func isExternal(_ line: String) -> Bool { externalLines.contains(line) }

    // MARK: Setting and cancelling

    /// Set what a finished line asks for.
    ///
    /// `origin` is the line this one was edited from, when the editor
    /// knows it. An edit that keeps the time words keeps the reminder
    /// and its time — "in 10 minutes" doesn't restart because a later
    /// word changed, and one that already fired doesn't fire again.
    /// New time words replace it. `restored`: the line came back whole —
    /// undone, pasted, unticked — rather than being typed.
    ///
    /// Nil when nothing is set: no time, or a time gone by.
    @discardableResult
    func commit(line: String, origin: String? = nil, restored: Bool = false, now: Date = Date()) -> Reminder? {
        guard let read = Reminders.read(line, now: now), case .at(let date) = read.reading else { return nil }
        if let existing = active(line) { return existing }
        externalLines.remove(line)

        if let origin, origin != line, let i = reminders.lastIndex(where: {
            $0.line == origin && !$0.archived && ($0.state != .cancelled || recent($0, now))
        }) {
            if reminders[i].phrase.lowercased() == read.phrase.lowercased() {
                reminders[i].line = line
                restore(i, now: now)
                return finishChange(at: i, now: now)
            }
            withdraw(i, now: now)
        }
        // The same line back moments after it went keeps its time. One
        // that already went off stays sent if the line was put back — but
        // typed again, it's a new reminder.
        if let i = reminders.lastIndex(where: {
            $0.line == line && $0.state == .cancelled && !$0.archived && recent($0, now) && ($0.fireDate > now || restored)
        }) {
            restore(i, now: now)
            return finishChange(at: i, now: now)
        }

        // Whole seconds: macOS fires on the second, and a fractional
        // time would read "not yet" for the moment after it fires.
        let whole = Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.up))
        reminders.append(Reminder(id: UUID().uuidString, line: line, phrase: read.phrase, fireDate: whole, state: .waiting))
        return finishChange(at: reminders.count - 1, now: now)
    }

    /// Bring a reminder back as it stood. One whose time came while it
    /// was cancelled was never sent, and says so.
    private func restore(_ i: Int, now: Date) {
        reminders[i].cancelledAt = nil
        if reminders[i].state == .cancelled { reminders[i].state = .waiting }
        if reminders[i].state == .scheduled, reminders[i].fireDate > now {
            // Same id: macOS replaces the pending one, now with the
            // line's new words.
            hand(i)
        }
    }

    private func withdraw(_ i: Int, now: Date) {
        if reminders[i].fireDate > now {
            // Even one waiting: taken back while notifications were off, it
            // was left with macOS, and would fire once they're back on.
            scheduler.cancel([reminders[i].id])
            reminders[i].handedOver = false
        }
        reminders[i].state = .cancelled
        reminders[i].cancelledAt = now
    }

    /// Nothing here removes a reminder, so `i` still points at it.
    private func finishChange(at i: Int, now: Date) -> Reminder {
        sync(now: now)
        save()
        refreshPermission(askIfUndecided: true, now: now)
        changed()
        return reminders[i]
    }

    /// Cancel reminders whose line is no longer in the note — deleted,
    /// ticked off, or changed — sent ones included, so a line typed
    /// again later is a new reminder. Run on every save; `commit` brings
    /// one back if its line returns within the revive window. A line
    /// being edited is left alone until the edit is finished.
    func reconcile(noteText: String, now: Date = Date()) {
        let editedFrom = Set(editing.values)
        let live = reminders.indices.filter {
            reminders[$0].state != .cancelled && !reminders[$0].archived && !editedFrom.contains(reminders[$0].line)
        }
        let present = Self.present(Set(live.map { reminders[$0].line }), in: noteText)
        var touched = false
        for i in live where !present.contains(reminders[i].line) {
            withdraw(i, now: now)
            touched = true
        }
        // History goes once it can't matter: cancellations past the
        // revive window, and filed reminders past their time.
        let before = reminders.count
        let oldest = now.addingTimeInterval(-Self.historyKept)
        reminders.removeAll {
            ($0.state == .cancelled && ($0.cancelledAt ?? .distantPast) < oldest) || ($0.archived && $0.fireDate < oldest)
        }
        if touched || reminders.count != before {
            sync(now: now)
            save()
            changed()
        }
    }

    /// The note is being filed to the Inbox, or set aside for a synced
    /// one: its reminders keep firing, though their lines leave the note.
    /// Lines also in `kept` — the note taking its place — stay as they are.
    func archive(noteText: String, keeping kept: String = "") {
        let live = reminders.indices.filter { reminders[$0].state != .cancelled && !reminders[$0].archived }
        let lines = Set(live.map { reminders[$0].line })
        let leaving = Self.present(lines, in: noteText).subtracting(Self.present(lines, in: kept))
        var touched = false
        for i in live where leaving.contains(reminders[i].line) {
            reminders[i].archived = true
            touched = true
        }
        if touched { save() }
    }

    /// A note came from disk — at launch, on reload, on a folder switch.
    /// Reminders whose lines are gone are cancelled; a line back within
    /// the revive window (a sync that briefly brought an older copy)
    /// keeps its reminder; any other reminder line stays unset here, and
    /// says so.
    func loaded(_ text: String, now: Date = Date()) {
        reconcile(noteText: text, now: now)
        let ns = text as NSString
        var external: Set<String> = []
        var revived = false
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            guard Reminders.mightBeReminder(ns, range) else { return }
            let line = ns.substring(with: range)
            guard Reminders.isReminder(line), self.active(line) == nil else { return }
            if let i = self.reminders.lastIndex(where: {
                $0.line == line && $0.state == .cancelled && !$0.archived && self.recent($0, now)
            }) {
                self.restore(i, now: now)
                revived = true
            } else {
                external.insert(line)
            }
        }
        externalLines = external
        if revived {
            sync(now: now)
            save()
        }
        changed()
    }

    // MARK: macOS

    /// Bring what macOS holds in line with what's set: while
    /// notifications can be shown, the soonest reminders still to fire,
    /// as many as macOS keeps; the rest wait. A reminder taken back before
    /// its time was never sent.
    private func sync(now: Date = Date()) {
        guard permissionChecked else { return }
        let ahead = reminders.indices
            .filter { reminders[$0].state != .cancelled && reminders[$0].fireDate > now }
            .sorted { reminders[$0].fireDate < reminders[$1].fireDate }
        let canHand = scheduler.canDeliver && permission == .allowed
        let held = canHand ? Set(ahead.prefix(Self.pendingLimit)) : []
        var touched = false
        for i in ahead where held.contains(i) != (reminders[i].state == .scheduled) {
            if held.contains(i) {
                reminders[i].state = .scheduled
                hand(i)
            } else {
                // Notifications turned off: macOS keeps it, but won't show
                // it. Past the limit: it goes back to waiting its turn.
                if canHand { scheduler.cancel([reminders[i].id]) }
                reminders[i].state = .waiting
                reminders[i].handedOver = false
            }
            touched = true
        }
        if touched { save() }
    }

    private func hand(_ i: Int) {
        reminders[i].handedOver = true
        let id = reminders[i].id
        scheduler.schedule(reminders[i]) { [weak self] taken in
            guard !taken, let self, let i = self.reminders.firstIndex(where: { $0.id == id }),
                  self.reminders[i].state == .scheduled else { return }
            self.reminders[i].state = .waiting
            self.reminders[i].handedOver = false
            self.save()
            self.changed()
        }
    }

    /// Put back what macOS lost (a hand-off cut short by quitting) and
    /// take away what it holds that isn't set (a removal cut short).
    private func repair() {
        scheduler.pending { [weak self] ids in
            guard let self else { return }
            let held = Set(ids)
            let ours = Set(self.reminders.filter { $0.state == .scheduled && $0.fireDate > Date() }.map(\.id))
            for i in self.reminders.indices where self.reminders[i].state == .scheduled
                && self.reminders[i].fireDate > Date() && !held.contains(self.reminders[i].id) {
                self.hand(i)
            }
            let strays = held.subtracting(ours)
            if self.loadedCleanly, !strays.isEmpty { self.scheduler.cancel(Array(strays)) }
        }
    }

    // MARK: Permission

    /// Ask macOS for the current setting — never trust an earlier
    /// answer: in the spike, a prompt left unanswered reported "not
    /// allowed", though Allow worked when clicked later. With
    /// `askIfUndecided`, a reminder waiting on an undecided setting
    /// brings the prompt back.
    func refreshPermission(askIfUndecided: Bool = false, now: Date = Date()) {
        scheduler.currentPermission { [weak self] current in
            guard let self else { return }
            let was = self.permission
            self.permission = current
            self.permissionChecked = true
            // Outside Applications macOS refuses without showing a
            // prompt; asking would only record a refusal.
            if current == .notDetermined, askIfUndecided, !self.asking, self.scheduler.canDeliver, self.hasWaiting() {
                self.asking = true
                self.scheduler.requestPermission { [weak self] granted in
                    guard let self else { return }
                    self.asking = false
                    // "Not granted" is also what an unanswered prompt
                    // says; the setting itself tells refused from undecided.
                    // Answered minutes later, perhaps: judged by then, not
                    // by when it was asked.
                    self.refreshPermission(now: self.clock())
                }
                return
            }
            self.sync(now: now)
            if current == .allowed { self.repair() }
            if current != was { self.changed() }
        }
    }

    private func hasWaiting(now: Date = Date()) -> Bool {
        reminders.contains { $0.state == .waiting && $0.fireDate > now }
    }

    func flush(timeout: TimeInterval = 1) {
        scheduler.flush(timeout: timeout)
    }

    // MARK: Finding

    func reminder(id: String) -> Reminder? {
        reminders.first { $0.id == id }
    }

    /// Where a reminder's line is now, or nil when it's gone — deleted,
    /// or filed to the Inbox with its note.
    func locate(_ reminder: Reminder, in text: String) -> NSRange? {
        guard !reminder.archived else { return nil }
        var found: NSRange?
        (text as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (text as NSString).length), options: .byLines
        ) { line, range, _, stop in
            if line == reminder.line {
                found = range
                stop.pointee = true
            }
        }
        return found
    }

    /// The reminder a line in the note stands for. Filed ones don't
    /// count — the same line typed in a fresh note is a new reminder.
    private func active(_ line: String) -> Reminder? {
        reminders.last { $0.line == line && $0.state != .cancelled && !$0.archived }
    }

    private func recent(_ reminder: Reminder, _ now: Date) -> Bool {
        guard let at = reminder.cancelledAt else { return true }
        return now.timeIntervalSince(at) <= Self.reviveWindow
    }

    // MARK: Lines

    /// Which of `candidates` are whole lines of `text`. This runs on every
    /// save. On a 1 MB note NSString finds a line that's there in about
    /// half a millisecond (one that isn't costs a full pass, ~3 ms); a
    /// byte search is quicker, but only after converting the note to
    /// UTF-8 (~15 ms); splitting it into lines costs ~80. So: NSString for
    /// a few, bytes for more, a split for very many.
    nonisolated static func present(_ candidates: Set<String>, in text: String) -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        if candidates.count <= 16 {
            let ns = text as NSString
            return candidates.filter { containsLine($0, in: ns) }
        }
        guard candidates.count <= 100 else { return candidates.intersection(lines(of: text)) }
        var text = text
        return text.withUTF8 { note in candidates.filter { containsLine($0, in: note) } }
    }

    nonisolated private static func containsLine(_ line: String, in ns: NSString) -> Bool {
        var search = NSRange(location: 0, length: ns.length)
        while search.length > 0 {
            let hit = ns.range(of: line, options: .literal, range: search)
            guard hit.location != NSNotFound else { return false }
            let startsLine = hit.location == 0 || isLineBreak(ns.character(at: hit.location - 1))
            let endsLine = NSMaxRange(hit) == ns.length || isLineBreak(ns.character(at: NSMaxRange(hit)))
            if startsLine && endsLine { return true }
            search = NSRange(location: hit.location + 1, length: ns.length - hit.location - 1)
        }
        return false
    }

    /// The breaks NSString ends a line at: LF, CR, NEL, LS, PS.
    nonisolated private static func isLineBreak(_ c: unichar) -> Bool {
        c == 0x0A || c == 0x0D || c == 0x85 || c == 0x2028 || c == 0x2029
    }

    /// Whether `line` is a whole line of `note`, both UTF-8. A match of
    /// valid UTF-8 in valid UTF-8 always starts and ends on a character,
    /// so only the bytes either side need checking.
    nonisolated private static func containsLine(_ line: String, in note: UnsafeBufferPointer<UInt8>) -> Bool {
        var line = line
        return line.withUTF8 { needle in
            guard let base = note.baseAddress, let bytes = needle.baseAddress, needle.count > 0 else { return false }
            var from = 0
            while note.count - from >= needle.count {
                guard let hit = memmem(base + from, note.count - from, bytes, needle.count) else { return false }
                let start = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(hit))
                if breakBefore(start, in: note), breakAfter(start + needle.count, in: note) { return true }
                from = start + 1
            }
            return false
        }
    }

    /// A line break ends at `index`, or it's the start.
    nonisolated private static func breakBefore(_ index: Int, in b: UnsafeBufferPointer<UInt8>) -> Bool {
        guard index > 0 else { return true }
        let c = b[index - 1]
        if c == 0x0A || c == 0x0D { return true }
        if c == 0x85 { return index >= 2 && b[index - 2] == 0xC2 }                       // NEL
        if c == 0xA8 || c == 0xA9 { return index >= 3 && b[index - 3] == 0xE2 && b[index - 2] == 0x80 }  // LS, PS
        return false
    }

    /// A line break starts at `index`, or it's the end.
    nonisolated private static func breakAfter(_ index: Int, in b: UnsafeBufferPointer<UInt8>) -> Bool {
        guard index < b.count else { return true }
        let c = b[index]
        if c == 0x0A || c == 0x0D { return true }
        if c == 0xC2 { return index + 1 < b.count && b[index + 1] == 0x85 }
        if c == 0xE2 { return index + 2 < b.count && b[index + 1] == 0x80 && (b[index + 2] == 0xA8 || b[index + 2] == 0xA9) }
        return false
    }

    nonisolated static func lines(of text: String) -> Set<String> {
        var lines = Set<String>()
        (text as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (text as NSString).length), options: .byLines
        ) { line, _, _, _ in
            if let line { lines.insert(line) }
        }
        return lines
    }

    // MARK: Disk

    /// Each entry on its own: one this version can't read (written by a
    /// newer one) is skipped, not the whole file — and the file is kept
    /// aside before anything overwrites it.
    private struct Entry: Decodable {
        let reminder: Reminder?
        init(from decoder: Decoder) throws { reminder = try? Reminder(from: decoder) }
    }

    private func load() {
        // While a copy is kept aside, a notification macOS holds may belong
        // to an entry only a newer Wisp can read: leave those be.
        let aside = fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
        loadedCleanly = !FileManager.default.fileExists(atPath: aside.path)
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let entries = try? JSONDecoder().decode([Entry].self, from: data)
        reminders = entries?.compactMap(\.reminder) ?? []
        if entries == nil || reminders.count != entries?.count {
            loadedCleanly = false
            // The first copy is the one with everything in it.
            if !FileManager.default.fileExists(atPath: aside.path) { try? data.write(to: aside, options: .atomic) }
        }
    }

    /// Dates as Foundation stores them, not ISO 8601 text (whole
    /// seconds only) or seconds since 1970 (one more rounding): a
    /// reminder reloads exactly as it was saved.
    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(reminders) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
        scheduleTick()
    }

    private func scheduleTick(now: Date = Date()) {
        tick?.invalidate()
        guard let next = reminders
            .filter({ $0.state != .cancelled && $0.fireDate > now })
            .map(\.fireDate).min() else { return }
        let timer = Timer(timeInterval: next.timeIntervalSince(now) + 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.sync()
                self.changed()
                self.scheduleTick()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    /// Lines' grey text changes. Posted once a turn of the run loop,
    /// however many changes it held.
    func changed() {
        guard !changePosted else { return }
        changePosted = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.changePosted = false
                NotificationCenter.default.post(name: Self.didChange, object: self)
            }
        }
    }
}

/// The real thing: local notifications through UNUserNotificationCenter.
@MainActor
final class SystemReminderScheduler: ReminderScheduling {
    var canDeliver: Bool { Self.isAppBundle && Self.isInApplicationsFolder(Bundle.main.bundlePath) }

    /// UNUserNotificationCenter raises an exception — killing the app —
    /// when asked for from a process that isn't an .app bundle: `swift
    /// run`, the release script's launch check. Nothing here touches it
    /// unless Wisp is running as a real app.
    nonisolated static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    nonisolated static func isInApplicationsFolder(_ bundlePath: String) -> Bool {
        bundlePath.hasSuffix(".app") && bundlePath.contains("/Applications/")
    }

    /// Hand-offs not yet acknowledged, so quitting can wait for them.
    private let inFlight = DispatchGroup()

    nonisolated static let category = "WispReminder"
    nonisolated static let doneAction = "WispReminderDone"

    /// The Done button on a reminder's notification. Handled without
    /// bringing Wisp forward: it ticks the line and that's all. macOS
    /// shows it on Persistent notifications; on the default, Temporary,
    /// it didn't appear even on hover — the tick in the editor is the
    /// way there.
    nonisolated static func registerActions() {
        guard isAppBundle else { return }
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [done], intentIdentifiers: [], options: []),
        ])
    }

    func schedule(_ reminder: Reminder, done: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard Self.isAppBundle else {
            done(false)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Wisp"
        content.body = Reminders.sentence(ofLine: reminder.line)
        content.sound = .default
        content.categoryIdentifier = Self.category
        // In UTC, so the moment is exact: no daylight-saving hour that
        // happens twice, and travelling doesn't move it.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var when = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        when.calendar = utc
        when.timeZone = utc.timeZone
        let request = UNNotificationRequest(
            identifier: reminder.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        )
        let group = inFlight
        group.enter()
        UNUserNotificationCenter.current().add(request) { error in
            group.leave()
            let taken = error == nil
            Task { @MainActor in done(taken) }
        }
    }

    func cancel(_ ids: [String]) {
        guard Self.isAppBundle else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func pending(_ done: @escaping @Sendable @MainActor ([String]) -> Void) {
        guard Self.isAppBundle else {
            done([])
            return
        }
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier)
            Task { @MainActor in done(ids) }
        }
    }

    func currentPermission(_ done: @escaping @Sendable @MainActor (ReminderPermission) -> Void) {
        guard Self.isAppBundle else {
            done(.denied)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let permission: ReminderPermission
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: permission = .allowed
            case .denied: permission = .denied
            default: permission = .notDetermined
            }
            Task { @MainActor in done(permission) }
        }
    }

    func requestPermission(_ done: @escaping @Sendable @MainActor (Bool) -> Void) {
        guard Self.isAppBundle else {
            done(false)
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in done(granted) }
        }
    }

    func flush(timeout: TimeInterval) {
        _ = inFlight.wait(timeout: .now() + timeout)
    }
}
