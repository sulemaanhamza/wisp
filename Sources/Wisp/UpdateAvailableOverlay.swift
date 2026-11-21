import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Shown over the editor when an update is available or already
/// downloaded. Two choices: install now (downloads first if needed,
/// then restarts) or later. It's shown once a version; after "Later"
/// the footer's indicator is what's left.
///
/// The note keeps the keyboard underneath, so the card must never sit
/// between someone and what they opened Wisp to write: the first key
/// typed is taken as "Later" and goes on to the note.
struct UpdateAvailableOverlay: View {
    let theme: Theme
    let state: UpdateState
    let highlights: [String]
    let onUpdate: () -> Void
    let onLater: () -> Void

    @State private var monitor: Any?

    var body: some View {
        ZStack {
            // Translucent backdrop — editor stays faintly visible so the
            // overlay reads as a notification, not a full-screen modal.
            OverlayScrim(theme: theme, onTap: onLater)

            VStack(spacing: 16) {
                // Non-interactive content gets its own arrow-cursor
                // wrapper. Keeping it separate from the button row
                // means the buttons' pointerCursor doesn't compete
                // with an outer arrowCursor on every mouse move.
                VStack(spacing: 14) {
                    Text(headline)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    if isDownloading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 2)
                    } else if let explanation {
                        Text(explanation)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if !highlights.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What's new")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .tracking(0.6)
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(highlights, id: \.self) { line in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("·").foregroundStyle(.tertiary)
                                        Text(line)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .arrowCursor()

                HStack(spacing: 10) {
                    Button(action: onUpdate) {
                        Text(primaryLabel)
                            .frame(minWidth: 130)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isDownloading)
                    .pointerCursor()

                    Button(action: onLater) {
                        Text("Later")
                            .frame(minWidth: 60)
                    }
                    .pointerCursor()
                }
            }
            .overlayCard(theme: theme)
        }
        .onAppear { startListening() }
        .onDisappear { stopListening() }
    }

    private var headline: String {
        switch state {
        case .available(let version, _):
            return "Wisp \(version) is available"
        case .downloading(let version):
            return "Downloading \(version)…"
        case .pending(let version):
            return "Wisp \(version) is ready to install"
        case .failed(let version):
            return "Wisp \(version) couldn't install itself"
        case .idle:
            return ""
        }
    }

    private var primaryLabel: String {
        switch state {
        case .pending: return "Restart Now"
        case .failed: return "Download from GitHub"
        default: return "Update & Restart"
        }
    }

    /// Shown instead of the release highlights when an install failed —
    /// the highlights are no longer the useful thing to say.
    private var explanation: String? {
        guard case .failed = state else { return nil }
        return "Wisp couldn't replace its own app bundle. This usually means /Applications needs an admin, or Wisp is running from Downloads. Download it and drag it in once, and updates will work from then on."
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    /// Esc is "Later", and so is anything else typed — which then goes
    /// on to the note, where it was headed. Return included: it used to
    /// look like the default button's key but never reached it, and a
    /// stray Return restarting Wisp mid-thought would be worse.
    private func startListening() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            onLater()
            return Int(event.keyCode) == kVK_Escape ? nil : event
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
