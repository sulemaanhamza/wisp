import AppKit

/// Dismisses the panel when the user clicks anywhere else.
///
/// Uses NSEvent's global monitor, which Apple documents as receiving
/// "copies of events the system posts to other applications" with no
/// permission needed for mouse events — only key events require
/// Accessibility access, and Wisp never asks for that. Two properties
/// of the API do the hard work for us:
///
/// - "your handler will not be called for events that are sent to your
///   own application" — so clicks inside the panel, on the menu bar
///   icon, or on any Wisp overlay never arrive here. There is nothing
///   to hit-test.
/// - Events are observe-only. We can't swallow the click, and we don't
///   want to: the user clicked their editor to work in it.
///
/// Off by default. Some people keep Wisp floating beside a browser and
/// would hate it vanishing every time they click away.
@MainActor
final class OutsideClickMonitor {
    static let enabledKey = "DismissOnOutsideClick"

    private var token: Any?
    private let onOutsideClick: () -> Void

    init(onOutsideClick: @escaping () -> Void) {
        self.onOutsideClick = onOutsideClick
    }

    var isActive: Bool { token != nil }

    func start() {
        guard token == nil else { return }
        token = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            // The global monitor calls back on the main thread, but the
            // closure isn't formally isolated; hop explicitly.
            Task { @MainActor in self?.onOutsideClick() }
        }
    }

    func stop() {
        if let token {
            NSEvent.removeMonitor(token)
            self.token = nil
        }
    }
}
