import SwiftUI

enum FontSize: String, CaseIterable {
    case small
    case medium
    case large

    var pointSize: CGFloat {
        switch self {
        case .small: return 17
        case .medium: return 20
        case .large: return 24
        }
    }

    var next: FontSize {
        let all = FontSize.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var text: String = "" {
        didSet {
            headings = text.extractHeadings()
            guard didLoad else { return }
            scheduleSave()
        }
    }
    @Published var headings: [Heading] = []
    @Published var focusToken: Int = 0
    @Published var scrollToken: Int = 0
    private(set) var scrollTarget: Int = 0
    @Published private(set) var placeholder: String = ""

    private static let placeholders = [
        "What's on your mind?",
        "Type your first thought…",
        "Write it down before it's gone.",
        "Capture it before you forget.",
        "Anything to remember?",
    ]
    @Published var fontSize: FontSize = .medium {
        didSet {
            guard didLoad else { return }
            UserDefaults.standard.set(fontSize.rawValue, forKey: "FontSize")
        }
    }
    @Published var theme: Theme = .dark {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "Theme")
            onThemeChange?(theme)
        }
    }

    /// PanelController subscribes to this so it can apply chrome changes
    /// (visualEffect material, tint color, panel appearance) when the
    /// theme flips. SwiftUI handles its own re-render via @Published.
    var onThemeChange: (@MainActor (Theme) -> Void)?

    private var didLoad = false
    private var saveTask: Task<Void, Never>?

    init() {
        if let saved = UserDefaults.standard.string(forKey: "Theme"),
           let t = Theme(rawValue: saved) {
            theme = t
        }
        if let saved = UserDefaults.standard.string(forKey: "FontSize"),
           let f = FontSize(rawValue: saved) {
            fontSize = f
        }
        if let loaded = try? String(contentsOf: Self.scratchpadURL, encoding: .utf8) {
            text = loaded
        }
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
        didLoad = true
    }

    func requestFocus() {
        focusToken &+= 1
    }

    func cycleFontSize() {
        fontSize = fontSize.next
        requestFocus()
    }

    func toggleTheme() {
        theme = theme.toggled
        requestFocus()
    }

    func jumpTo(_ heading: Heading) {
        scrollTarget = heading.lineStart
        scrollToken &+= 1
    }

    func refreshPlaceholder() {
        placeholder = Self.placeholders.randomElement() ?? Self.placeholders[0]
    }

    /// Force a synchronous flush — call from applicationWillTerminate so an
    /// in-flight debounced save isn't lost when the user quits.
    func flushSave() {
        saveTask?.cancel()
        try? Self.write(text)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = text
        saveTask = Task.detached(priority: .background) {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            try? Self.write(snapshot)
        }
    }

    nonisolated private static func write(_ text: String) throws {
        try text.write(to: scratchpadURL, atomically: true, encoding: .utf8)
    }

    nonisolated private static var scratchpadURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Wisp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("scratchpad.md")
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var updater: Updater

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(headings: model.headings) { heading in
                model.jumpTo(heading)
            }
            ZStack(alignment: .topLeading) {
                MinimalTextEditor(
                    text: $model.text,
                    focusToken: model.focusToken,
                    scrollToken: model.scrollToken,
                    scrollTarget: model.scrollTarget,
                    fontSize: model.fontSize,
                    theme: model.theme
                )
                .padding(.horizontal, 28)
                .padding(.top, model.headings.isEmpty ? 28 : 4)
                .padding(.bottom, 4)
                if model.text.isEmpty {
                    Text(model.placeholder)
                        .font(.custom("Charter", size: model.fontSize.pointSize))
                        .foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                        .padding(.horizontal, 28)
                        .padding(.top, model.headings.isEmpty ? 28 : 4)
                }
            }
            BottomBar(
                wordCount: wordCount,
                fontSize: model.fontSize,
                onCycleFontSize: { model.cycleFontSize() },
                theme: model.theme,
                onToggleTheme: { model.toggleTheme() },
                updateState: updater.state,
                onUpdateClick: { updater.handleClick() }
            )
        }
        // Border drawn here in SwiftUI rather than via CALayer
        // borderColor/borderWidth on the panel chrome — CALayer border
        // draws at rectangular bounds and leaked at the rounded corners
        // on first render. SwiftUI's strokeBorder draws inside the shape,
        // doesn't have a rectangular phase, and clips correctly.
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(borderColor, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var borderColor: Color {
        switch model.theme {
        case .light: return Color.black.opacity(0.12)
        case .dark: return Color.clear
        }
    }

    private var wordCount: Int {
        var count = 0
        let text = model.text
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { _, _, _, _ in
            count += 1
        }
        return count
    }
}
