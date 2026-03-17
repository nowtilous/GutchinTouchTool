import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var gestureLog = GestureLog.shared
    @State private var showLog = true
    @State private var showTouchVisualizer = true
    @AppStorage("GTTAppearance") private var appearance: String = "dark"
    @Environment(\.openSettings) private var openSettingsAction

    private var isDark: Bool { appearance == "dark" }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar — fixed width, not draggable
            AppSidebar()
                .frame(width: 200, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            Divider()

            if appState.showStatistics {
                StatisticsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    TriggerListPanel()
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)

                    ActionListPanel()
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)

                    ConfigurationPanel()
                        .frame(minWidth: 280, idealWidth: 350)
                }
            }

            if showLog || showTouchVisualizer {
                VStack(spacing: 0) {
                    if showLog {
                        LogSidePanel(entries: gestureLog.entries)
                    }

                    if showTouchVisualizer {
                        if showLog { Divider() }
                        VStack(spacing: 4) {
                            HStack {
                                Text("Live Touch")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 4)

                            LiveTouchView()
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 8)
                        }
                        .frame(height: showLog ? 180 : 220)
                        .background(Color(nsColor: .controlBackgroundColor))
                    }
                }
                .frame(width: 280)
                .transition(.move(edge: .trailing))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Text("GutchinTouchTool")
                        .font(.headline)
                    UpdateBadgeView(updateChecker: appState.updateChecker)
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            appState.toggleGlobalEnabled()
                        }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(appState.globalEnabled ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(appState.globalEnabled ? "ON" : "OFF")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(appState.globalEnabled ? .green : .red)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill((appState.globalEnabled ? Color.green : Color.red).opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(appState.globalEnabled ? "Disable all gestures" : "Enable all gestures")
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { withAnimation { showTouchVisualizer.toggle() } }) {
                    Label("Touch Viz", systemImage: "hand.point.up.braille.fill")
                        .foregroundStyle(showTouchVisualizer ? .cyan : .secondary)
                }
                Button(action: { withAnimation { showLog.toggle() } }) {
                    Label("Console", systemImage: "terminal.fill")
                        .foregroundStyle(showLog ? .green : .secondary)
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appearance = isDark ? "light" : "dark"
                    }
                }) {
                    Label("Appearance", systemImage: isDark ? "moon.fill" : "sun.max.fill")
                        .foregroundStyle(isDark ? .indigo : .yellow)
                }
                Button(action: {
                    openSettings()
                }) {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .help("App Settings")
            }
        }
        .preferredColorScheme(appearance == "system" ? nil : (isDark ? .dark : .light))
    }

    private func openSettings() {
        openSettingsAction()
    }
}
