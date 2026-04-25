import Foundation
import AppKit

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
    private let releasesPageURL = URL(string: "https://github.com/sulemaanhamza/wisp/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    init() {
        if let pending = UserDefaults.standard.string(forKey: "PendingUpdateVersion") {
            state = .pending(version: pending)
        }
    }

    func check() async {
        if case .pending = state { return }
        if case .downloading = state { return }
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

    /// Interim click handler: open the releases page in a browser. Replaced
    /// in a follow-up commit with an in-app download.
    func handleClick() {
        switch state {
        case .available:
            NSWorkspace.shared.open(releasesPageURL)
        case .pending:
            NSWorkspace.shared.open(releasesPageURL)
        case .idle, .downloading:
            break
        }
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
