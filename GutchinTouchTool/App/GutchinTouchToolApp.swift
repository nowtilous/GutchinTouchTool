import SwiftUI
import ServiceManagement
import AppKit

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
                .environmentObject(appState)
                .tabItem { Label("General", systemImage: "gearshape") }
            BackupSettingsView()
                .tabItem { Label("Backups", systemImage: "externaldrive.fill") }
            AppearanceSettingsView()
                .environmentObject(appState)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 480)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Startup")
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            NSLog("[GTT] Failed to update login item: %@", error.localizedDescription)
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Show Menu Bar Icon", isOn: $showMenuBarIcon)
            }
            .padding(.leading, 4)

            Divider()

            Text("Import / Export")
                .font(.headline)
            HStack(spacing: 12) {
                Button {
                    exportPreset()
                } label: {
                    Label("Export Preset", systemImage: "square.and.arrow.up")
                }
                Button {
                    importPreset()
                } label: {
                    Label("Import Preset", systemImage: "square.and.arrow.down")
                }
            }
            .padding(.leading, 4)

            Divider()

            Text("Help")
                .font(.headline)
            Button {
                showTutorialFromSettings()
            } label: {
                Label("Show Tutorial", systemImage: "questionmark.circle")
            }
            .padding(.leading, 4)

            Divider()

            HStack {
                Text("Preset File")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(PresetManager.presetFilePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Reveal") {
                    NSWorkspace.shared.selectFile(PresetManager.presetFilePath, inFileViewerRootedAtPath: "")
                }
                .controlSize(.mini)
            }

            Spacer()

            Button("Reset All Settings to Defaults", role: .destructive) {
                resetAllSettings()
            }
            .foregroundColor(.red)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showTutorialFromSettings() {
        // Capture Settings window before we switch focus (it's key when we're in Settings)
        let settingsWindow = NSApp.keyWindow
        // Bring main window to front
        (NSApp.delegate as? AppDelegate)?.showMainWindow()
        // Close Settings window
        settingsWindow?.close()
        // Request tutorial on main window
        appState.showTutorialRequested = true
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

    private func resetAllSettings() {
        let alert = NSAlert()
        alert.messageText = "Reset All Settings?"
        alert.informativeText = "This will reset all preferences to defaults. Your triggers and actions will not be affected."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            let keys = ["GTTGlobalEnabled", "GTTAccentColor", "GTTAppearance",
                        "GTTPressDragThreshold", "GTTTipTapMinRestTime",
                        "GTTSuppressMouseDuringDrawing", "launchAtLogin", "showMenuBarIcon", "GTTHasSeenTutorial"]
            for key in keys {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

struct BackupSettingsView: View {
    @State private var backupsEnabled = PresetManager.backupsEnabled
    @State private var customPath = UserDefaults.standard.string(forKey: "GTTBackupPath") ?? ""
    @State private var maxBackups = Double(PresetManager.maxBackups)
    @State private var backups: [(date: Date, size: Int64, url: URL)] = []

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Automatic Backups")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable automatic backups", isOn: $backupsEnabled)
                    .onChange(of: backupsEnabled) { _, newValue in
                        PresetManager.backupsEnabled = newValue
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup Location")
                        .foregroundColor(.secondary)
                    HStack {
                        TextField("Default (~/.gutchintouchtool_backups)", text: $customPath)
                            .font(.system(size: 11, design: .monospaced))
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.canCreateDirectories = true
                            if panel.runModal() == .OK, let url = panel.url {
                                customPath = url.path
                                UserDefaults.standard.set(url.path, forKey: "GTTBackupPath")
                            }
                        }
                        .controlSize(.small)
                        if !customPath.isEmpty {
                            Button("Reset") {
                                customPath = ""
                                UserDefaults.standard.removeObject(forKey: "GTTBackupPath")
                            }
                            .controlSize(.small)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Max Backups: \(Int(maxBackups))")
                        .foregroundColor(.secondary)
                    Slider(value: $maxBackups, in: 1...20, step: 1)
                        .frame(width: 200)
                        .onChange(of: maxBackups) { _, newValue in
                            PresetManager.maxBackups = Int(newValue)
                        }
                }
            }
            .padding(.leading, 4)

            Divider()

            Text("Existing Backups")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                if backups.isEmpty {
                    Text("No backups yet")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(Array(backups.enumerated()), id: \.offset) { _, backup in
                        HStack {
                            Text(dateFormatter.string(from: backup.date))
                                .font(.system(size: 12))
                            Text(ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Reveal") {
                                NSWorkspace.shared.selectFile(backup.url.path, inFileViewerRootedAtPath: "")
                            }
                            .controlSize(.small)
                        }
                    }
                }

                Button("Reveal Backup Folder") {
                    NSWorkspace.shared.open(PresetManager.backupDirectory)
                }
                .controlSize(.small)
            }
            .padding(.leading, 4)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { backups = PresetManager.listBackups() }
    }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("GTTAppearance") private var appearance: String = "dark"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Theme")
                .font(.headline)
            Picker("Appearance", selection: $appearance) {
                Text("Dark").tag("dark")
                Text("Light").tag("light")
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .labelsHidden()
            .padding(.leading, 4)

            Divider()

            Text("Accent Color")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(AccentColorChoice.allCases) { choice in
                    Circle()
                        .fill(choice.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: appState.accentColorChoice == choice ? 2.5 : 0)
                        )
                        .shadow(color: appState.accentColorChoice == choice ? choice.color.opacity(0.6) : .clear, radius: 4)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.accentColorChoice = choice
                                UserDefaults.standard.set(choice.rawValue, forKey: "GTTAccentColor")
                            }
                        }
                }
            }
            .padding(.leading, 4)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AboutSettingsView: View {
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "hand.point.up.braille.fill")
                .font(.system(size: 48))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .purple, .pink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text("GutchinTouchTool")
                .font(.title2.bold())
            Text("Version \(appVersion)")
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
