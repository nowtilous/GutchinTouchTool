import SwiftUI

struct UpdateBadgeView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @State private var showingConfirmation = false

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var isUpdateAvailable: Bool {
        if case .available = updateChecker.status { return true }
        return false
    }

    var body: some View {
        Button(action: { handleTap() }) {
            HStack(spacing: 4) {
                if isUpdateAvailable {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
                Text("v\(currentVersion)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        isUpdateAvailable
                            ? LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [.blue.opacity(0.8), .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(statusHelp)
        .alert("Update Available", isPresented: $showingConfirmation) {
            Button("Update & Restart") {
                if case .available(_, let url) = updateChecker.status {
                    Task { await updateChecker.downloadAndInstall(url: url) }
                }
            }
            Button("Later", role: .cancel) {}
        } message: {
            if case .available(let version, _) = updateChecker.status {
                Text("Version \(version) is available. The app will download the update, restart, and apply it.")
            }
        }
    }

    private var statusHelp: String {
        switch updateChecker.status {
        case .available(let version, _):
            return "v\(version) available — click to update"
        case .downloading(let progress):
            return "Downloading update: \(Int(progress * 100))%"
        case .checking:
            return "Checking for updates…"
        case .error(let msg):
            return "Update check failed: \(msg). Click to retry."
        case .upToDate:
            return "You're on the latest version"
        }
    }

    private func handleTap() {
        switch updateChecker.status {
        case .available:
            showingConfirmation = true
        case .error:
            Task { await updateChecker.checkForUpdate() }
        default:
            break
        }
    }
}
