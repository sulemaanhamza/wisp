import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Shown over the editor when an update is available or already
/// downloaded. Two choices: install now (downloads first if needed,
/// then restarts) or dismiss for this panel-open. The dismissal is
/// per-session — opening the panel again brings the overlay back as
/// long as the update is still pending.
struct UpdateAvailableOverlay: View {
    let theme: Theme
    let state: UpdateState
    let onUpdate: () -> Void
    let onLater: () -> Void

    @State private var monitor: Any?

    var body: some View {
        ZStack {
            // Translucent backdrop — editor stays faintly visible so the
            // overlay reads as a notification, not a full-screen modal.
            Rectangle()
                .fill(theme == .dark
                      ? Color(white: 0.05).opacity(0.55)
                      : Color(white: 1.0).opacity(0.55))
                .contentShape(Rectangle())
                .onTapGesture { onLater() }
                .arrowCursor()

            VStack(spacing: 16) {
                // Non-interactive content gets its own arrow-cursor
                // wrapper. Keeping it separate from the button row
                // means the buttons' pointerCursor doesn't compete
                // with an outer arrowCursor on every mouse move.
                VStack(spacing: 16) {
                    Text(headline)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    if isDownloading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.vertical, 2)
                    }
                }
                .arrowCursor()

                HStack(spacing: 10) {
                    Button(action: onUpdate) {
                        Text(primaryLabel)
                            .frame(minWidth: 130)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isDownloading)
                    .pointerCursor()

                    Button(action: onLater) {
                        Text("Later")
                            .frame(minWidth: 60)
                    }
                    .keyboardShortcut(.cancelAction)
                    .pointerCursor()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.18), radius: 18, y: 6)
            )
            .frame(maxWidth: 360)
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
        case .idle:
            return ""
        }
    }

    private var primaryLabel: String {
        switch state {
        case .pending: return "Restart Now"
        default: return "Update & Restart"
        }
    }

    private var isDownloading: Bool {
        if case .downloading = state { return true }
        return false
    }

    private var cardFill: Color {
        theme == .dark
            ? Color(white: 0.13)
            : Color(white: 0.99)
    }

    private var borderColor: Color {
        theme == .dark
            ? Color(white: 1.0).opacity(0.10)
            : Color.black.opacity(0.10)
    }

    /// Esc — treat as "Later". The panel.onCancel cascade in
    /// PanelController also handles this, but listening locally means
    /// the overlay stays in charge of its own dismissal even if
    /// onCancel ordering changes later.
    private func startListening() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                onLater()
                return nil
            }
            return event
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
