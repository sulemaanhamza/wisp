import ServiceManagement

/// Thin wrapper over `SMAppService.mainApp`. The system tracks the
/// registered/unregistered state itself, so we just read & toggle.
///
/// Note: SMAppService needs a properly bundled .app to register. Running
/// via `swift run` will fail because the executable isn't in a bundle the
/// system recognizes — that's expected. The shipped .app from
/// scripts/build-app.sh works.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // No in-app surface for this — the menu checkmark just won't
            // flip on the next read. Logged so dev mode is debuggable.
            print("LaunchAtLogin: \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }
}
