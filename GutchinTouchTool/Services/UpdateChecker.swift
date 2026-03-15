import Foundation
import AppKit

// MARK: - Network abstraction for testability

protocol NetworkSession: Sendable {
    func fetchData(from url: URL) async throws -> (Data, URLResponse)
    func downloadFile(from url: URL) async throws -> (URL, URLResponse)
}

extension URLSession: NetworkSession {
    func fetchData(from url: URL) async throws -> (Data, URLResponse) {
        try await data(from: url)
    }

    func downloadFile(from url: URL) async throws -> (URL, URLResponse) {
        try await download(from: url)
    }
}

// MARK: - GitHub API models

struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: String

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    var dmgURL: URL? {
        guard let asset = assets.first(where: { $0.name.hasSuffix(".dmg") }),
              let url = URL(string: asset.browserDownloadUrl) else { return nil }
        return url
    }
}

// MARK: - Update status

enum UpdateStatus: Equatable {
    case upToDate
    case available(version: String, downloadURL: URL)
    case checking
    case downloading(progress: Double)
    case error(String)
}

// MARK: - UpdateChecker

@MainActor
class UpdateChecker: ObservableObject {
    @Published var status: UpdateStatus = .upToDate

    private let session: NetworkSession
    private let currentVersion: String
    private var checkTimer: Timer?

    static let releaseURL = URL(string: "https://api.github.com/repos/nowtilous/GutchinTouchTool/releases/latest")!

    init(session: NetworkSession = URLSession.shared,
         currentVersion: String? = nil) {
        self.session = session
        self.currentVersion = currentVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
    }

    // MARK: - Version comparison

    /// Returns true if `remote` is a newer semver than `local`.
    nonisolated static func isNewer(_ remote: String, than local: String) -> Bool {
        let remoteParts = remote.split(separator: ".").compactMap { Int($0) }
        let localParts = local.split(separator: ".").compactMap { Int($0) }

        // Must have at least one valid numeric component
        guard !remoteParts.isEmpty, !localParts.isEmpty else { return false }

        // Pad to 3 components
        let r = remoteParts + Array(repeating: 0, count: max(0, 3 - remoteParts.count))
        let l = localParts + Array(repeating: 0, count: max(0, 3 - localParts.count))

        for i in 0..<3 {
            if r[i] > l[i] { return true }
            if r[i] < l[i] { return false }
        }
        return false
    }

    // MARK: - Check for updates

    func checkForUpdate() async {
        status = .checking
        do {
            let (data, _) = try await session.fetchData(from: Self.releaseURL)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            guard Self.isNewer(release.version, than: currentVersion) else {
                status = .upToDate
                return
            }

            guard let dmgURL = release.dmgURL else {
                status = .error("No DMG found in release")
                return
            }

            status = .available(version: release.version, downloadURL: dmgURL)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Periodic checks

    func startPeriodicChecks(interval: TimeInterval = 3600) {
        Task { await checkForUpdate() }
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.checkForUpdate()
            }
        }
    }

    func stopPeriodicChecks() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - Download and install

    func downloadAndInstall(url: URL) async {
        status = .downloading(progress: 0)
        do {
            let (tmpURL, _) = try await session.downloadFile(from: url)

            // Move to a known location so hdiutil can access it
            let dmgPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("GutchinTouchTool_update.dmg")
            try? FileManager.default.removeItem(at: dmgPath)
            try FileManager.default.moveItem(at: tmpURL, to: dmgPath)

            status = .downloading(progress: 1.0)
            installUpdate(dmgPath: dmgPath)
        } catch {
            status = .error("Download failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Install (mount DMG, swap app, relaunch)

    private func installUpdate(dmgPath: URL) {
        let currentAppPath = Bundle.main.bundlePath
        // If running from DerivedData, install to /Applications instead
        let destination: String
        if currentAppPath.contains("DerivedData") || currentAppPath.contains("Build/Products") {
            destination = "/Applications/GutchinTouchTool.app"
        } else {
            destination = currentAppPath
        }

        let mountPoint = "/tmp/GutchinTouchTool_update_mount"
        let pid = ProcessInfo.processInfo.processIdentifier

        // Shell script that outlives the app: waits for exit, swaps, relaunches
        let script = """
        #!/bin/bash
        # Wait for the app to quit
        while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done
        # Mount the DMG
        mkdir -p "\(mountPoint)"
        hdiutil attach "\(dmgPath.path)" -nobrowse -quiet -mountpoint "\(mountPoint)"
        # Find the .app in the mounted volume
        APP=$(find "\(mountPoint)" -maxdepth 1 -name "*.app" -print -quit)
        if [ -n "$APP" ]; then
            rm -rf "\(destination)"
            cp -R "$APP" "\(destination)"
        fi
        # Cleanup
        hdiutil detach "\(mountPoint)" -quiet
        rm -f "\(dmgPath.path)"
        # Relaunch
        open "\(destination)"
        rm -f /tmp/gtt_update.sh
        """

        let scriptPath = "/tmp/gtt_update.sh"
        do {
            try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            try process.run()

            // Quit the app so the script can replace it
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        } catch {
            status = .error("Install failed: \(error.localizedDescription)")
        }
    }
}
