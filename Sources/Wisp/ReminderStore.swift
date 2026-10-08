import Foundation
import UserNotifications

/// One reminder that was set. Kept on this Mac only.
struct Reminder: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        /// Handed to macOS.
        case scheduled
        /// Set, but notifications aren't allowed (yet) — handed to macOS
        /// as soon as they are.
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
    var created: Date
    var state: State
    /// Filed to the Inbox with its note: it still fires, and the
    /// note's absence doesn't cancel it.
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
    /// unticked, or mid-edit when a save ran — keeps its original time.
    static let reviveWindow: TimeInterval = 10 * 60

    let fileURL: URL
    let scheduler: ReminderScheduling
    private(set) var reminders: [Reminder] = []
    private(set) var permission: ReminderPermission = .notDetermined
    /// Reminder lines that arrived from disk with nothing set for them.
    private var externalLines: Set<String> = []

    init(fileURL: URL, scheduler: ReminderScheduling) {
        self.fileURL = fileURL
        self.scheduler = scheduler
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? Self.decoder.decode([Reminder].self, from: data) {
            reminders = saved
        }
    }

    // MARK: What a line shows

    /// The grey text after `line`, or nil when it isn't a reminder.
    func label(forLine line: String, now: Date = Date()) -> Reminders.Label? {
        guard Reminders.isReminder(line) else { return nil }
        if let reminder = active(line) {
            switch reminder.state {
            case .scheduled:
                return reminder.fireDate <= now ? .sent(reminder.fireDate) : .due(reminder.fireDate)
            case .waiting:
                // Never handed to macOS: it can't have been sent, whatever
                // the clock says.
                if reminder.fireDate <= now { return .notSent }
                return permission == .denied ? .notificationsOff : .due(reminder.fireDate)
            case .cancelled:
                return nil
            }
        }
        if externalLines.contains(line) { return .notOnThisMac }
        guard let read = Reminders.read(line, now: now) else { return nil }
        switch read.reading {
        case .past: return .past
        case .noTime: return .noTime
        case .at(let date):
            if !scheduler.canDeliver { return .outsideApplications }
            if permission == .denied { return .notificationsOff }
            return .due(date)
        }
    }

    // MARK: Setting and cancelling

    /// Set what a finished line asks for. Nil when it sets nothing: no
    /// time, a time gone by, or an app macOS won't deliver to.
    @discardableResult
    func commit(line: String, noteText: String, now: Date = Date()) -> Reminder? {
        guard let read = Reminders.read(line, now: now), case .at(let date) = read.reading else { return nil }
        if let existing = active(line) { return existing }
        guard scheduler.canDeliver else { return nil }
        externalLines.remove(line)
        let noteLines = Self.lines(of: noteText)

        // The same line, cancelled moments ago: cut and pasted, or
        // unticked. It keeps the time it was set for.
        if let i = reminders.lastIndex(where: {
            $0.line == line && $0.state == .cancelled && recent($0, now) && $0.fireDate > now
        }) {
            return revive(i, as: line, now: now)
        }
        // An edited line: a reminder whose own line has gone, with the
        // same time phrase. "In 10 minutes" doesn't restart because a
        // word after it changed.
        if !read.phrase.isEmpty, let i = reminders.lastIndex(where: {
            $0.phrase.lowercased() == read.phrase.lowercased() && $0.fireDate > now && !$0.archived
                && !noteLines.contains($0.line) && ($0.state != .cancelled || recent($0, now))
        }) {
            return revive(i, as: line, now: now)
        }

        reminders.append(Reminder(
            id: UUID().uuidString, line: line, phrase: read.phrase,
            fireDate: date, created: now, state: .waiting
        ))
        save()
        refreshPermission(askIfUndecided: true)
        changed()
        return reminders.last
    }

    private func revive(_ i: Int, as line: String, now: Date) -> Reminder {
        if reminders[i].state == .scheduled { scheduler.cancel([reminders[i].id]) }
        reminders[i].line = line
        reminders[i].state = .waiting
        reminders[i].cancelledAt = nil
        save()
        refreshPermission(askIfUndecided: true)
        changed()
        return reminders[i]
    }

    /// Cancel reminders whose line is no longer in the note — deleted,
    /// ticked off, or changed. Run on every save; `commit` brings one
    /// back if the line returns within the revive window.
    func reconcile(noteText: String, now: Date = Date()) {
        let noteLines = Self.lines(of: noteText)
        var touched = false
        // Sent ones too: delete a line and type it again, and it's a new
        // reminder, not the old one's "sent". Only one still pending is
        // withdrawn from macOS — a delivered one stays in Notification
        // Center.
        for i in reminders.indices where reminders[i].state != .cancelled && !reminders[i].archived
            && !noteLines.contains(reminders[i].line) {
            if reminders[i].state == .scheduled, reminders[i].fireDate > now { scheduler.cancel([reminders[i].id]) }
            reminders[i].state = .cancelled
            reminders[i].cancelledAt = now
            touched = true
        }
        externalLines.formIntersection(noteLines)
        // Old history goes: cancellations past the revive window, and
        // anything that fired more than a month ago.
        let before = reminders.count
        reminders.removeAll {
            ($0.state == .cancelled && ($0.cancelledAt ?? .distantPast) < now.addingTimeInterval(-86_400))
                || $0.fireDate < now.addingTimeInterval(-30 * 86_400)
        }
        if touched || reminders.count != before {
            save()
            changed()
        }
    }

    /// The note is being filed to the Inbox: its reminders keep firing,
    /// though their lines leave the note.
    func archive(noteText: String) {
        let noteLines = Self.lines(of: noteText)
        var touched = false
        for i in reminders.indices where reminders[i].state != .cancelled && noteLines.contains(reminders[i].line) {
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
    /// allowed", though Allow worked when clicked later.
    func refreshPermission(askIfUndecided: Bool = false) {
        scheduler.currentPermission { [weak self] current in
            guard let self else { return }
            if current == .notDetermined, askIfUndecided, self.reminders.contains(where: { $0.state == .waiting }) {
                self.scheduler.requestPermission { [weak self] granted in
                    guard let self else { return }
                    self.permission = granted ? .allowed : .denied
                    if granted { self.scheduleWaiting() }
                    self.changed()
                }
                return
            }
            self.permission = current
            if current == .allowed { self.scheduleWaiting() }
            self.changed()
        }
    }

    private func scheduleWaiting(now: Date = Date()) {
        var touched = false
        for i in reminders.indices where reminders[i].state == .waiting && reminders[i].fireDate > now {
            reminders[i].state = .scheduled
            scheduler.schedule(reminders[i])
            touched = true
        }
        if touched { save() }
    }

    // MARK: Finding

    func reminder(id: String) -> Reminder? {
        reminders.first { $0.id == id }
    }

    /// Where a reminder's line is now: the same line, or failing that
    /// a line with the same time phrase. Nil when it's gone.
    func locate(_ reminder: Reminder, in text: String) -> NSRange? {
        var exact: NSRange?
        var similar: NSRange?
        (text as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (text as NSString).length), options: .byLines
        ) { line, range, _, stop in
            guard let line else { return }
            if line == reminder.line {
                exact = range
                stop.pointee = true
            } else if similar == nil, !reminder.phrase.isEmpty,
                      Reminders.read(line)?.phrase.lowercased() == reminder.phrase.lowercased() {
                similar = range
            }
        }
        return exact ?? similar
    }

    private func active(_ line: String) -> Reminder? {
        reminders.last { $0.line == line && $0.state != .cancelled }
    }

    private func recent(_ reminder: Reminder, _ now: Date) -> Bool {
        guard let at = reminder.cancelledAt else { return true }
        return now.timeIntervalSince(at) <= Self.reviveWindow
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

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // Dates as Foundation stores them, not ISO 8601 text (whole
        // seconds only) or seconds since 1970 (one more rounding): a
        // reminder reloads exactly as it was saved.
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private func save() {
        guard let data = try? Self.encoder.encode(reminders) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

/// The real thing: local notifications through UNUserNotificationCenter.
@MainActor
final class SystemReminderScheduler: ReminderScheduling {
    var canDeliver: Bool { Self.isInApplicationsFolder(Bundle.main.bundlePath) }

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

    func schedule(_ reminder: Reminder) {
        guard Self.isAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = "Wisp"
        content.body = Reminders.sentence(ofLine: reminder.line)
        content.sound = .default
        content.userInfo = ["id": reminder.id]
        // The time zone is part of the trigger, so it fires at the
        // moment it was set for even if you travel or the clocks change.
        let calendar = Calendar.current
        var when = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
        when.calendar = calendar
        when.timeZone = calendar.timeZone
        let request = UNNotificationRequest(
            identifier: reminder.id, content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
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
}
