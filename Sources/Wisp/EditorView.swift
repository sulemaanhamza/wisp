import SwiftUI

enum FontSize: Int, CaseIterable {
    case small = 14
    case medium = 17
    case large = 22

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
            guard didLoad else { return }
            scheduleSave()
        }
    }
    @Published var focusToken: Int = 0
    @Published var fontSize: FontSize = .medium

    private var didLoad = false
    private var saveTask: Task<Void, Never>?

    init() {
        if let loaded = try? String(contentsOf: Self.scratchpadURL, encoding: .utf8) {
            text = loaded
        }
        didLoad = true
    }

    func requestFocus() {
        focusToken &+= 1
    }

    func cycleFontSize() {
        fontSize = fontSize.next
        requestFocus()
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
            MinimalTextEditor(
                text: $model.text,
                focusToken: model.focusToken,
                fontSize: model.fontSize
            )
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 4)
            BottomBar(
                wordCount: wordCount,
                fontSize: model.fontSize,
                onCycleFontSize: { model.cycleFontSize() },
                updateState: updater.state,
                onUpdateClick: { updater.handleClick() }
            )
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
