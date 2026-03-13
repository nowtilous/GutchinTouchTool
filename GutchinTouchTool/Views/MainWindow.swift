import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var gestureLog = GestureLog.shared
    @State private var showLog = true
    @State private var showTouchVisualizer = true
    @AppStorage("GTTAppearance") private var appearance: String = "dark"

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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { withAnimation { showTouchVisualizer.toggle() } }) {
                    Label("Touch Viz", systemImage: "hand.point.up.braille.fill")
                        .foregroundStyle(showTouchVisualizer ? .cyan : .secondary)
                }
                Button(action: { withAnimation { showLog.toggle() } }) {
                    Label("Console", systemImage: "terminal.fill")
                        .foregroundStyle(showLog ? .green : .secondary)
                }
                Button(action: { exportPreset() }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                Button(action: { importPreset() }) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appearance = isDark ? "light" : "dark"
                    }
                }) {
                    Label("Appearance", systemImage: isDark ? "moon.fill" : "sun.max.fill")
                        .foregroundStyle(isDark ? .indigo : .yellow)
                }
            }
        }
        .preferredColorScheme(appearance == "system" ? nil : (isDark ? .dark : .light))
    }

    private func exportPreset() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(appState.currentPreset.name).bttpreset"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                appState.exportPreset(to: url)
            }
        }
    }

    private func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                appState.importPreset(from: url)
            }
        }
    }
}
