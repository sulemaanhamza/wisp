import Foundation
import AppKit

private let pendingVersionKey = "PendingUpdateVersion"
private let pendingZipKey = "PendingUpdateZipPath"

enum UpdateState: Equatable {
    case idle
    case available(version: String, zipURL: URL)
    case downloading(version: String)
    case pending(version: String)
}

@MainActor
final class Updater: ObservableObject {
    @Published private(set) var state: UpdateState = .idle

    private let owner = "sulemaanhamza"
    private let repo = "wisp"
    private var lastCheckedAt: Date?
    /// Set when the user clicks "Update & Restart" while still in
    /// `.available`. Drives an automatic apply+exit the moment download
    /// completes, so the user only has to click once.
    private var pendingAutoApply = false

    /// Re-check no more often than this (politeness toward GitHub's
    /// 60/hour unauth rate limit, and avoids redundant fetches when the
    /// user is rapidly toggling the panel).
    nonisolated static let checkThrottle: TimeInterval = 60

    nonisolated static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    init() {
        if let pending = UserDefaults.standard.string(forKey: pendingVersionKey) {
            state = .pending(version: pending)
        }
    }

    /// What the primary update button should do for a given state.
    /// Pulled out as a pure function so the decision is unit-testable.
    enum ButtonAction: Equatable {
        case startDownload
        case applyAndRestart
        case noop
    }
    nonisolated static func buttonAction(for state: UpdateState) -> ButtonAction {
        switch state {
        case .available: return .startDownload
        case .pending: return .applyAndRestart
        case .idle, .downloading: return .noop
        }
    }

    /// `true` when enough time has passed since the last check to make
    /// a fresh network call worth it. Pure so it's testable.
    nonisolated static func shouldCheck(
        now: Date,
        lastCheckedAt: Date?,
        throttle: TimeInterval = checkThrottle
    ) -> Bool {
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= throttle
    }

    func check() async {
        if case .pending = state { return }
        if case .downloading = state { return }
        guard Self.shouldCheck(now: Date(), lastCheckedAt: lastCheckedAt) else { return }
        lastCheckedAt = Date()
        do {
            let release = try await fetchLatestRelease()
            let remote = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let local = Self.currentVersion
            guard remote.compare(local, options: .numeric) == .orderedDescending else { return }
            guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else { return }
            state = .available(version: remote, zipURL: asset.browserDownloadUrl)
        } catch {
            // Silent — never bother the user with a network hiccup.
        }
    }

    func handleClick() {
        switch state {
        case .available:
            Task { await startDownload() }
        case .pending:
            applyAndExit()
        case .idle, .downloading:
            break
        }
    }

    /// Single-button "Update & Restart" entry point used by the
    /// in-panel overlay. Downloads first if needed, then auto-applies
    /// once the download finishes.
    func startUpdateAndRestart() {
        switch Self.buttonAction(for: state) {
        case .startDownload:
            pendingAutoApply = true
            Task { await startDownload() }
        case .applyAndRestart:
            applyAndExit()
        case .noop:
            break
        }
    }

    /// Called when the user dismisses the update overlay mid-download.
    /// We can't cleanly abort the in-flight URLSession download from
    /// here, but we can stop ourselves from auto-applying (and quitting
    /// the user out of their session) when it eventually completes.
    func cancelAutoApply() {
        pendingAutoApply = false
    }

    private func applyAndExit() {
        if Self.applyPendingUpdateIfPossible() {
            exit(0)
        }
    }

    private func startDownload() async {
        guard case .available(let version, let zipURL) = state else { return }
        state = .downloading(version: version)
        do {
            let dest = try await Self.downloadZip(from: zipURL, version: version)
            UserDefaults.standard.set(version, forKey: pendingVersionKey)
            UserDefaults.standard.set(dest.path, forKey: pendingZipKey)
            state = .pending(version: version)
            if pendingAutoApply {
                pendingAutoApply = false
                applyAndExit()
            }
        } catch {
            // Roll back to available so the user can retry.
            pendingAutoApply = false
            state = .available(version: version, zipURL: zipURL)
        }
    }

    /// Called from main.swift before NSApplication.run. If a pending update
    /// was downloaded in a previous session, this swaps the running bundle
    /// for the new one, spawns a tiny helper to relaunch us once we exit,
    /// and returns true. Caller is expected to exit(0).
    nonisolated static func applyPendingUpdateIfPossible() -> Bool {
        let defaults = UserDefaults.standard
        guard let version = defaults.string(forKey: pendingVersionKey),
              let zipPath = defaults.string(forKey: pendingZipKey) else {
            return false
        }
        // Clear keys unconditionally — if apply fails, we don't want to loop
        // on every launch retrying a broken zip.
        defaults.removeObject(forKey: pendingVersionKey)
        defaults.removeObject(forKey: pendingZipKey)
        _ = version  // currently unused, but reserved for future logging
        return apply(zipPath: zipPath)
    }

    nonisolated private static func apply(zipPath: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: zipPath) else { return false }
        // Only try to swap a real .app bundle. During `swift run` Bundle.main
        // points at a bare executable; nothing to replace.
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else { return false }

        let staging = NSTemporaryDirectory() + "wisp-update-\(UUID().uuidString)"

        do {
            try fm.createDirectory(atPath: staging, withIntermediateDirectories: true)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zipPath, staging]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else { return false }

            let newBundle = "\(staging)/Wisp.app"
            guard fm.fileExists(atPath: newBundle) else { return false }

            // Move-then-move-then-cleanup so a failure mid-replace can roll back.
            let backup = bundlePath + ".old-\(UUID().uuidString)"
            try fm.moveItem(atPath: bundlePath, toPath: backup)
            do {
                try fm.moveItem(atPath: newBundle, toPath: bundlePath)
            } catch {
                try? fm.moveItem(atPath: backup, toPath: bundlePath)
                return false
            }
            try? fm.removeItem(atPath: backup)
            try? fm.removeItem(atPath: zipPath)
            try? fm.removeItem(atPath: staging)

            // Spawn a detached sh that waits for our PID to die, then opens
            // the (now-replaced) bundle. We exit; macOS launches the new us.
            let pid = ProcessInfo.processInfo.processIdentifier
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = [
                "-c",
                "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open '\(bundlePath)'"
            ]
            try relaunch.run()
            return true
        } catch {
            return false
        }
    }

    nonisolated private static func downloadZip(from url: URL, version: String) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        let dir = updatesDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("Wisp-\(version).zip")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    nonisolated private static func updatesDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Wisp/Updates")
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: request)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GitHubRelease.self, from: data)
    }
}
