import SwiftUI

struct MainWindow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var gestureLog = GestureLog.shared
    @State private var showLog = true

    var body: some View {
        HStack(spacing: 0) {
            HSplitView {
                AppSidebar()
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)

                TriggerListPanel()
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)

                ActionListPanel()
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)

                ConfigurationPanel()
                    .frame(minWidth: 280, idealWidth: 350)
            }

            if showLog {
                LogSidePanel(entries: gestureLog.entries)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
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
            }
        }
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
