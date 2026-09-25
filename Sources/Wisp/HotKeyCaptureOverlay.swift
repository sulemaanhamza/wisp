import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Modal overlay shown while the user is rebinding the global hotkey.
/// Listens for the next valid key combo (must include at least one
/// modifier), then asks the parent to attempt Carbon registration.
/// On success the parent dismisses; on failure (combo in use system-
/// wide) the error is shown inline and capture mode keeps listening.
struct HotKeyCaptureOverlay: View {
    let theme: Theme
    /// Returns nil on success or a user-facing error message otherwise.
    let onTryRegister: (HotKey) -> String?
    let onSuccess: () -> Void
    let onCancel: () -> Void

    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            // No click-to-cancel here. Stray clicks while the user is
            // thinking about a combo shouldn't drop them out of capture
            // mode. Esc still cancels.
            OverlayScrim(theme: theme)

            VStack(spacing: 12) {
                Text("Press your shortcut")
                    .font(.system(size: 17, weight: .semibold))
                Text("must include ⌘, ⌥, or ⌃ — Esc to cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .overlayCard(theme: theme)
        }
        .onAppear { startListening() }
        .onDisappear { stopListening() }
    }

    private func startListening() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape {
                onCancel()
                return nil
            }

            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let hotKey = HotKey(
                keyCode: UInt32(event.keyCode),
                modifiers: HotKey.carbonModifiers(from: mods)
            )

            guard HotKey.hasRequiredModifier(hotKey.modifiers) else {
                errorMessage = "Add ⌘, ⌥, or ⌃ — shift on its own isn't enough."
                return nil
            }
            if let reason = HotKey.reservedReason(for: hotKey) {
                errorMessage = reason
                return nil
            }

            if let err = onTryRegister(hotKey) {
                errorMessage = err
                // Stay listening so the user can immediately try another.
            } else {
                onSuccess()
            }
            return nil
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
