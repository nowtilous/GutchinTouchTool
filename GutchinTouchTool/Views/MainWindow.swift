import SwiftUI

// Touch Viz — hand scale on hover
struct TouchVizToolbarButton: View {
    var isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("Touch Viz", systemImage: "hand.point.up.braille.fill")
                .foregroundStyle(isActive || isHovering ? Color.cyan : .secondary)
                .scaleEffect(isHovering ? 1.12 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// Console — cursor pulse on hover
struct ConsoleToolbarButton: View {
    var isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("Console", systemImage: "terminal.fill")
                .foregroundStyle(isActive || isHovering ? Color.green : .secondary)
                .scaleEffect(isHovering ? 1.12 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// Appearance — sun/moon scale on hover
struct AppearanceToolbarButton: View {
    var isDark: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("Appearance", systemImage: isDark ? "moon.fill" : "sun.max.fill")
                .foregroundStyle(isDark ? Color.indigo : .yellow)
                .scaleEffect(isHovering ? 1.12 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// Settings — gear subtle rotation on hover
struct SettingsToolbarButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("Settings", systemImage: "gearshape.fill")
                .foregroundStyle(isHovering ? Color.primary : .secondary)
                .rotationEffect(.degrees(isHovering ? 25 : 0))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var gestureLog = GestureLog.shared
    @AppStorage("GTTShowLog") private var showLog = false
    @AppStorage("GTTShowTouchVisualizer") private var showTouchVisualizer = false
    @State private var showTutorial = !UserDefaults.hasSeenTutorial
    @State private var tutorialFrames: [TutorialRegion: CGRect] = [:]
    @AppStorage("GTTAppearance") private var appearance: String = "dark"
    @Environment(\.openSettings) private var openSettingsAction

    private var isDark: Bool { appearance == "dark" }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar — fixed width, not draggable
            AppSidebar()
                .frame(width: 200, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .tutorialAnchor(.sidebar)

            Divider()

            if appState.showStatistics {
                StatisticsView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    TriggerListPanel()
                        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                        .tutorialAnchor(.triggers)

                    ActionListPanel()
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)
                        .tutorialAnchor(.actions)

                    ConfigurationPanel()
                        .frame(minWidth: 280, idealWidth: 350)
                        .tutorialAnchor(.config)
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
        .coordinateSpace(name: "tutorialOverlay")
        .onPreferenceChange(TutorialFramePreferenceKey.self) { tutorialFrames = $0 }
        .overlay {
            if showTutorial {
                TutorialOverlayView(isPresented: $showTutorial, frames: tutorialFrames)
                    .environmentObject(appState)
            }
        }
        .onChange(of: appState.showTutorialRequested) { _, requested in
            if requested {
                showTutorial = true
                appState.showTutorialRequested = false
            }
        }
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
                TouchVizToolbarButton(isActive: showTouchVisualizer) {
                    withAnimation { showTouchVisualizer.toggle() }
                }

                ConsoleToolbarButton(isActive: showLog) {
                    withAnimation { showLog.toggle() }
                }

                AppearanceToolbarButton(isDark: isDark) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        appearance = isDark ? "light" : "dark"
                    }
                }

                SettingsToolbarButton { openSettings() }
                    .help("App Settings")
            }
        }
        .preferredColorScheme(appearance == "system" ? nil : (isDark ? .dark : .light))
        .onAppear {
            LiveTouchState.shared.isVisualizerActive = appState.isMainWindowVisible && showTouchVisualizer
        }
        .onChange(of: showTouchVisualizer) { _, newValue in
            LiveTouchState.shared.isVisualizerActive = newValue && appState.isMainWindowVisible
        }
        .onChange(of: appState.isMainWindowVisible) { _, isVisible in
            LiveTouchState.shared.isVisualizerActive = isVisible && showTouchVisualizer
        }
    }

    private func openSettings() {
        openSettingsAction()
    }
}
