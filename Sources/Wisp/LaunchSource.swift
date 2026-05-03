import Foundation

/// Tells us whether the current launch was user-initiated (clicked from
/// Applications, Spotlight, Finder) or driven by macOS at login.
///
/// AppKit puts an `NSApplicationLaunchIsDefaultLaunchKey` BOOL into the
/// launch notification's userInfo: `true` for user launches, `false`
/// when the app was opened as a login item. Pulled out as a pure helper
/// so the launch-detection logic is unit-testable without spinning up
/// NSApplication.
enum LaunchSource {
    static let isDefaultLaunchKey = "NSApplicationLaunchIsDefaultLaunchKey"

    /// `true` when the user kicked off this launch, `false` when macOS
    /// auto-launched at login. Defaults to `true` if the key is missing
    /// so we never silently suppress the panel on a launch path AppKit
    /// doesn't annotate.
    static func isUserInitiated(launchUserInfo userInfo: [AnyHashable: Any]?) -> Bool {
        (userInfo?[isDefaultLaunchKey] as? Bool) ?? true
    }
}
