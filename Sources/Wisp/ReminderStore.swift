import Foundation
import UserNotifications

/// One reminder that was set. Kept on this Mac only.
///
/// A field added later must be optional: a Reminders.json that no
/// longer decodes loses every reminder in it.
struct Reminder: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        /// Handed to macOS.
        case scheduled
        /// Set, but not handed to macOS (yet): notifications aren't
        /// allowed, or Wisp isn't in an Applications folder.
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
    /// It has been handed to macOS at least once — so if its time has
    /// gone, it was sent.
    var handedOver = false
    /// Filed to the Inbox with its note: it still fires, though its
    /// line is no longer in the note.
    var archived = false
    var cancelledAt: Date?
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
    func schedule(_ reminder: Reminder)
    func cancel(_ ids: [String])
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
    /// or unticked — keeps the time it was set for.
    static let reviveWindow: TimeInterval = 10 * 60

    let fileURL: URL
    let scheduler: ReminderScheduling
    private(set) var reminders: [Reminder] = []
    private(set) var permission: ReminderPermission = .notDetermined
    /// Reminder lines that arrived from disk with nothing set for them.
    private var externalLines: Set<String> = []
    private var asking = false
    /// Readings of lines with nothing set, for the current minute. A
    /// restyle asks about every reminder line, and reading the time is
    /// the costly part. Labels show minutes, so reusing a reading within
    /// one can't show a wrong time.
    private var readings: [String: (reading: Reminders.Reading, phrase: String)?] = [:]
    private var readingsMinute = 0
    /// Fires when the next reminder is due, so its line turns to "sent"
    /// (or "not sent") while the panel is open — macOS only tells a
    /// running app that's in front.
    private var tick: Timer?

    init(fileURL: URL, scheduler: ReminderScheduling) {
        self.fileURL = fileURL
        self.scheduler = scheduler
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Reminder].self, from: data) {
            reminders = saved
        }
        scheduleTick()
    }

    // MARK: What a line shows

    /// The grey text after `line`, or nil when it isn't a reminder.
    func label(forLine line: String, now: Date = Date()) -> Reminders.Label? {
        guard Reminders.isReminder(line) else { return nil }
        if let reminder = active(line) { return label(for: reminder, now: now) }
        guard let read = reading(line, now: now) else { return nil }
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
            // Turned off since it was set: macOS will drop it.
            return permission == .denied ? .notificationsOff : .set(reminder.fireDate)
        }
        if !scheduler.canDeliver { return .outsideApplications }
        switch permission {
        case .denied: return .notificationsOff
        case .notDetermined: return .needsPermission
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
    /// New time words replace it.
    ///
    /// Nil when nothing is set: no time, or a time gone by.
    @discardableResult
    func commit(line: String, origin: String? = nil, now: Date = Date()) -> Reminder? {
        guard let read = Reminders.read(line, now: now), case .at(let date) = read.reading else { return nil }
        if let existing = active(line) { return existing }
        externalLines.remove(line)

        if let origin, origin != line, let i = reminders.lastIndex(where: {
            $0.line == origin && !$0.archived && ($0.state != .cancelled || recent($0, now))
        }) {
            if reminders[i].phrase.lowercased() == read.phrase.lowercased() {
                reminders[i].line = line
                return restore(i, now: now)
            }
            withdraw(i, now: now)
        }
        // The same line back moments after it went: cut and pasted, or
        // unticked. It keeps its time. Only one still to fire: a line
        // typed again after its reminder went off is a new reminder,
        // not the old one's "sent".
        if let i = reminders.lastIndex(where: {
            $0.line == line && $0.state == .cancelled && !$0.archived && recent($0, now) && $0.fireDate > now
        }) {
            return restore(i, now: now)
        }

        // Whole seconds: macOS fires on the second, and a fractional
        // time would read "not yet" for the moment after it fires.
        let whole = Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.up))
        reminders.append(Reminder(id: UUID().uuidString, line: line, phrase: read.phrase, fireDate: whole, state: .waiting))
        deliver(reminders.count - 1, now: now)
        return finishChange(at: reminders.count - 1)
    }

    /// Bring back a reminder, as it stood: waiting to be handed over if
    /// its time is ahead, or as it ended if its time has gone.
    private func restore(_ i: Int, now: Date) -> Reminder {
        reminders[i].cancelledAt = nil
        if reminders[i].fireDate > now {
            if reminders[i].state == .scheduled {
                // Same id: macOS replaces the pending one, now with the
                // line's new words.
                scheduler.schedule(reminders[i])
            } else {
                deliver(i, now: now)
            }
        } else if reminders[i].state == .cancelled {
            reminders[i].state = reminders[i].handedOver ? .scheduled : .waiting
        }
        return finishChange(at: i)
    }

    /// Hand a reminder to macOS when that can happen now — permission
    /// already known — so it's done even if Wisp is quitting; otherwise
    /// it waits, and a permission check follows.
    private func deliver(_ i: Int, now: Date) {
        guard reminders[i].fireDate > now else { return }
        if scheduler.canDeliver, permission == .allowed {
            reminders[i].state = .scheduled
            reminders[i].handedOver = true
            scheduler.schedule(reminders[i])
        } else {
            reminders[i].state = .waiting
        }
    }

    private func withdraw(_ i: Int, now: Date) {
        if reminders[i].state == .scheduled, reminders[i].fireDate > now { scheduler.cancel([reminders[i].id]) }
        reminders[i].state = .cancelled
        reminders[i].cancelledAt = now
    }

    private func finishChange(at i: Int) -> Reminder {
        let reminder = reminders[i]
        save()
        refreshPermission(askIfUndecided: true)
        changed()
        return reminder
    }

    /// Cancel reminders whose line is no longer in the note — deleted,
    /// ticked off, or changed — sent ones included, so a line typed
    /// again later is a new reminder. Run on every save; `commit` brings
    /// one back if its line returns within the revive window.
    func reconcile(noteText: String, now: Date = Date()) {
        let live = reminders.indices.filter { reminders[$0].state != .cancelled && !reminders[$0].archived }
        let staleCancelled = reminders.contains {
            $0.state == .cancelled && ($0.cancelledAt ?? .distantPast) < now.addingTimeInterval(-86_400)
        }
        guard !live.isEmpty || !externalLines.isEmpty || staleCancelled else { return }
        let present = Self.present(Set(live.map { reminders[$0].line }).union(externalLines), in: noteText)
        var touched = false
        for i in live where !present.contains(reminders[i].line) {
            withdraw(i, now: now)
            touched = true
        }
        externalLines.formIntersection(present)
        // History goes once it can't come back: a cancellation older
        // than a day, well past the revive window.
        let before = reminders.count
        reminders.removeAll { $0.state == .cancelled && ($0.cancelledAt ?? .distantPast) < now.addingTimeInterval(-86_400) }
        if touched || reminders.count != before {
            save()
            changed()
        }
    }

    /// The note is being filed to the Inbox, or set aside for a synced
    /// one: its reminders keep firing, though their lines leave the note.
    func archive(noteText: String) {
        let live = reminders.indices.filter { reminders[$0].state != .cancelled && !reminders[$0].archived }
        guard !live.isEmpty else { return }
        let present = Self.present(Set(live.map { reminders[$0].line }), in: noteText)
        var touched = false
        for i in live where present.contains(reminders[i].line) {
            reminders[i].archived = true
            touched = true
        }
        if touched { save() }
    }

    /// A note came from disk. Its reminder lines with nothing set for
    /// them stay unset here, and say so.
    func noteLoaded(_ text: String) {
        for line in Self.lines(of: text) where Reminders.isReminder(line) && active(line) == nil {
            externalLines.insert(line)
        }
        changed()
    }

    // MARK: Permission

    /// Ask macOS for the current setting — never trust an earlier
    /// answer: in the spike, a prompt left unanswered reported "not
    /// allowed", though Allow worked when clicked later. With
    /// `askIfUndecided`, a reminder waiting on an undecided setting
    /// brings the prompt back.
    func refreshPermission(askIfUndecided: Bool = false) {
        scheduler.currentPermission { [weak self] current in
            guard let self else { return }
            self.permission = current
            // Outside Applications macOS refuses without showing a
            // prompt; asking would only record a refusal.
            if current == .notDetermined, askIfUndecided, !self.asking, self.scheduler.canDeliver, self.hasWaiting() {
                self.asking = true
                self.scheduler.requestPermission { [weak self] granted in
                    guard let self else { return }
                    self.asking = false
                    if granted {
                        self.permission = .allowed
                        self.scheduleWaiting()
                        self.changed()
                        return
                    }
                    // "Not granted" is also what an unanswered prompt
                    // says; the setting itself tells refused from undecided.
                    self.scheduler.currentPermission { [weak self] after in
                        self?.permission = after
                        self?.changed()
                    }
                }
                return
            }
            if current == .allowed { self.scheduleWaiting() }
            self.changed()
        }
    }

    private func hasWaiting(now: Date = Date()) -> Bool {
        reminders.contains { $0.state == .waiting && $0.fireDate > now }
    }

    private func scheduleWaiting(now: Date = Date()) {
        guard scheduler.canDeliver else { return }
        var touched = false
        for i in reminders.indices where reminders[i].state == .waiting && reminders[i].fireDate > now {
            deliver(i, now: now)
            touched = true
        }
        if touched { save() }
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

    /// Which of `candidates` are whole lines of `text`. This runs on
    /// every save: splitting a 1 MB note into lines takes ~80 ms, a
    /// byte search for one line ~0.5 ms — so a search each, unless
    /// there are very many.
    nonisolated static func present(_ candidates: Set<String>, in text: String) -> Set<String> {
        guard !candidates.isEmpty else { return [] }
        guard candidates.count <= 100 else { return candidates.intersection(lines(of: text)) }
        var text = text
        return text.withUTF8 { note in candidates.filter { containsLine($0, in: note) } }
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

    /// A line break (any of CharacterSet.newlines) ends at `index`, or
    /// it's the start.
    nonisolated private static func breakBefore(_ index: Int, in b: UnsafeBufferPointer<UInt8>) -> Bool {
        guard index > 0 else { return true }
        let c = b[index - 1]
        if (0x0A...0x0D).contains(c) { return true }
        if c == 0x85 { return index >= 2 && b[index - 2] == 0xC2 }                       // U+0085
        if c == 0xA8 || c == 0xA9 { return index >= 3 && b[index - 3] == 0xE2 && b[index - 2] == 0x80 }  // U+2028/9
        return false
    }

    /// A line break starts at `index`, or it's the end.
    nonisolated private static func breakAfter(_ index: Int, in b: UnsafeBufferPointer<UInt8>) -> Bool {
        guard index < b.count else { return true }
        let c = b[index]
        if (0x0A...0x0D).contains(c) { return true }
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
            .filter({ $0.state != .cancelled && !$0.archived && $0.fireDate > now })
            .map(\.fireDate).min() else { return }
        let timer = Timer(timeInterval: next.timeIntervalSince(now) + 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.changed()
                self?.scheduleTick()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        tick = timer
    }

    func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
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
    /// bringing Wisp forward: it ticks the line and that's all.
    nonisolated static func registerActions() {
        guard isAppBundle else { return }
        let done = UNNotificationAction(identifier: doneAction, title: "Done", options: [])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: category, actions: [done], intentIdentifiers: [], options: []),
        ])
    }

    func schedule(_ reminder: Reminder) {
        guard Self.isAppBundle else { return }
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
        UNUserNotificationCenter.current().add(request) { _ in group.leave() }
    }

    func cancel(_ ids: [String]) {
        guard Self.isAppBundle else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
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
