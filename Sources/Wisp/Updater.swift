import Foundation
import AppKit
import CryptoKit

private let pendingVersionKey = "PendingUpdateVersion"
private let pendingZipKey = "PendingUpdateZipPath"
private let failedVersionKey = "FailedUpdateVersion"

enum UpdateState: Equatable {
    case idle
    case available(version: String, zipURL: URL)
    case downloading(version: String)
    case pending(version: String)
    /// The download was fine but the bundle couldn't be replaced —
    /// /Applications owned by an admin, a read-only volume, the app
    /// running translocated out of Downloads. Without this the same
    /// update was silently offered again on every single open.
    case failed(version: String)
}

/// Where to send someone whose automatic update didn't take.
let releasesPageURL = URL(string: "https://github.com/sulemaanhamza/wisp/releases/latest")!

@MainActor
final class Updater: ObservableObject {
    @Published private(set) var state: UpdateState = .idle
    /// Short "what's new" bullets for the available release, shown in the
    /// update card. Empty until a release is found (or for older releases
    /// without the highlights convention).
    @Published private(set) var highlights: [String] = []

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

    /// sha256 GitHub published for the pending asset, checked after the
    /// download so a truncated or swapped zip is never unpacked over
    /// the running app. nil for releases published before the API
    /// started returning digests.
    private var expectedDigest: String?

    init() {
        if let failed = UserDefaults.standard.string(forKey: failedVersionKey) {
            state = .failed(version: failed)
        } else if let pending = UserDefaults.standard.string(forKey: pendingVersionKey) {
            state = .pending(version: pending)
        }
    }

    /// `true` when we're running from a real .app bundle. `swift run`
    /// reports version 0.0.0, so without this check every contributor
    /// gets an update card the first time they open the panel — and the
    /// bundle swap has nothing to swap anyway.
    nonisolated static var isBundled: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// What the primary update button should do for a given state.
    /// Pulled out as a pure function so the decision is unit-testable.
    enum ButtonAction: Equatable {
        case startDownload
        case applyAndRestart
        case openReleases
        case noop
    }
    nonisolated static func buttonAction(for state: UpdateState) -> ButtonAction {
        switch state {
        case .available: return .startDownload
        case .pending: return .applyAndRestart
        case .failed: return .openReleases
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
        guard Self.isBundled else { return }
        if case .pending = state { return }
        if case .downloading = state { return }
        if case .failed = state { return }
        guard Self.shouldCheck(now: Date(), lastCheckedAt: lastCheckedAt) else { return }
        lastCheckedAt = Date()
        do {
            let release = try await fetchLatestRelease()
            let remote = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            let local = Self.currentVersion
            guard remote.compare(local, options: .numeric) == .orderedDescending else { return }
            guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else { return }
            highlights = ReleaseNotes.highlights(from: release.body ?? "")
            expectedDigest = Self.sha256Hex(fromDigestField: asset.digest)
            state = .available(version: remote, zipURL: asset.browserDownloadUrl)
        } catch {
            // Silent — never bother the user with a network hiccup.
        }
    }

    /// Clear a failed update so the next check can offer it again —
    /// the user may have moved Wisp somewhere writable since.
    func retryAfterFailure() {
        guard case .failed = state else { return }
        UserDefaults.standard.removeObject(forKey: failedVersionKey)
        lastCheckedAt = nil
        state = .idle
        Task { await check() }
    }

    func handleClick() {
        switch state {
        case .available:
            Task { await startDownload() }
        case .pending:
            applyAndExit()
        case .failed:
            NSWorkspace.shared.open(releasesPageURL)
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
        case .openReleases:
            NSWorkspace.shared.open(releasesPageURL)
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
        guard case .pending(let version) = state else { return }
        if Self.applyPendingUpdateIfPossible() {
            exit(0)
        }
        // Couldn't swap the bundle. Say so and point at the download
        // rather than offering the same broken install again.
        UserDefaults.standard.set(version, forKey: failedVersionKey)
        state = .failed(version: version)
    }

    private func startDownload() async {
        guard case .available(let version, let zipURL) = state else { return }
        state = .downloading(version: version)
        do {
            let dest = try await Self.downloadZip(
                from: zipURL, version: version, expecting: expectedDigest
            )
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
        if apply(zipPath: zipPath) { return true }
        // Remember the failure so the next launch can explain itself
        // instead of quietly offering the same update forever.
        defaults.set(version, forKey: failedVersionKey)
        return false
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

    enum UpdateError: Error {
        case digestMismatch
    }

    nonisolated private static func downloadZip(
        from url: URL, version: String, expecting digest: String?
    ) async throws -> URL {
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        if let digest {
            let actual = try sha256Hex(ofFileAt: tempURL)
            guard actual.caseInsensitiveCompare(digest) == .orderedSame else {
                try? FileManager.default.removeItem(at: tempURL)
                throw UpdateError.digestMismatch
            }
        }
        let dir = updatesDirectory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent("Wisp-\(version).zip")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return dest
    }

    /// GitHub reports asset digests as "sha256:<hex>". Anything else
    /// (or nothing) means we can't verify, and we don't pretend to.
    /// Pure so it's testable.
    nonisolated static func sha256Hex(fromDigestField field: String?) -> String? {
        guard let field, field.hasPrefix("sha256:") else { return nil }
        let hex = String(field.dropFirst("sha256:".count))
        guard hex.count == 64, hex.allSatisfy(\.isHexDigit) else { return nil }
        return hex
    }

    /// Streamed so a large zip never lands in memory whole.
    nonisolated private static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
            /// "sha256:<hex>". Absent on older releases.
            let digest: String?
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
