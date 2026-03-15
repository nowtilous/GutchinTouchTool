import SwiftUI

struct UpdateBadgeView: View {
    @ObservedObject var updateChecker: UpdateChecker
    @State private var showingConfirmation = false
    @State private var pulsing = false
    @State private var borderPhase: CGFloat = 0

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var isUpdateAvailable: Bool {
        if case .available = updateChecker.status { return true }
        return false
    }

    private var gradientColors: [Color] {
        if case .available = updateChecker.status {
            return [.orange, .red]
        }
        return [.blue, .purple]
    }

    var body: some View {
        Button(action: { handleTap() }) {
            Text("v\(currentVersion)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            .linearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .overlay {
                    if isUpdateAvailable {
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2.5, dash: [5, 4], dashPhase: borderPhase))
                            .foregroundStyle(
                                .linearGradient(
                                    colors: [.red, .yellow, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .shadow(color: .red.opacity(0.6), radius: 3)
                            .onAppear {
                                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                                    borderPhase = -(5 + 4)
                                }
                            }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if isUpdateAvailable {
                        ZStack {
                            Circle()
                                .fill(.red.opacity(0.4))
                                .frame(width: 16, height: 16)
                                .scaleEffect(pulsing ? 1.4 : 1.0)
                                .opacity(pulsing ? 0 : 0.6)
                            Circle()
                                .fill(.red)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.8), lineWidth: 1.5)
                                )
                        }
                        .offset(x: 5, y: -5)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                                pulsing = true
                            }
                        }
                    }
                }
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
