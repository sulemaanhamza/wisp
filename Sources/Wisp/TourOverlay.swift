import SwiftUI
import AppKit
import Carbon.HIToolbox

/// First-run welcome card. Three essential tips and a single "Got it"
/// (Return works too). Dismisses on a click outside the card or Esc.
struct TourOverlay: View {
    let theme: Theme
    /// The summon shortcut as it is now, not the default.
    var hotKey: String = HotKey.default.displayString
    let onDismiss: () -> Void

    @State private var monitor: Any?

    var body: some View {
        ZStack {
            OverlayScrim(theme: theme, onTap: onDismiss)

            VStack(alignment: .leading, spacing: 16) {
                Text("Welcome to Wisp")
                    .font(.system(size: 17, weight: .semibold))

                tip(hotKey, "summon Wisp from anywhere", key: true)
                tip("Menu bar icon", "right-click for fonts, transparency, and your shortcut")
                tip("⌘/", "every shortcut and format — or the ? in the footer", key: true)

                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text("Got it")
                            .frame(minWidth: 72)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .pointerCursor()
                }
                .padding(.top, 8)
            }
            .overlayCard(theme: theme, maxWidth: 400)
        }
        .onAppear { startListening() }
        .onDisappear { stopListening() }
    }

    /// Return means "Got it". A keyboard shortcut on the button can't do
    /// this: the note keeps keyboard focus under the card, so it would
    /// take the Return first — as a newline in the text behind.
    private func startListening() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter:
                onDismiss()
                return nil
            default:
                return event
            }
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    @ViewBuilder
    private func tip(_ name: String, _ description: String, key: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Group {
                if key {
                    Keycap(text: name)
                } else {
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, alignment: .leading)
            Text(description)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
