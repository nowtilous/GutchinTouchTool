import SwiftUI

@main
struct GutchinTouchToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environmentObject(appState)
                .tint(appState.accentColorChoice.color)
                .frame(minWidth: 1300, minHeight: 650)
                .task {
                    appDelegate.appState = appState
                    appState.startMonitoring()
                    appDelegate.onReady = { [appState] in
                        appState.startMonitoring()
                    }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 700)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 450, height: 300)
    }
}

struct GeneralSettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
            Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
        }
        .padding()
    }
}
