import SwiftUI

struct AppSidebar: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAppPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Applications")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { showingAppPicker = true }) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showingAppPicker) {
                    AppPickerView { app in
                        appState.addAppTarget(app)
                        showingAppPicker = false
                    }
                    .frame(width: 300, height: 400)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // App List
            List(selection: Binding(
                get: { appState.selectedAppTarget.id },
                set: { id in
                    if let app = appState.currentPreset.appTargets.first(where: { $0.id == id }) {
                        appState.selectedAppTarget = app
                        appState.selectedTrigger = nil
                        appState.selectedAction = nil
                    }
                }
            )) {
                ForEach(appState.currentPreset.appTargets) { app in
                    AppTargetRow(app: app)
                        .tag(app.id)
                        .contextMenu {
                            if !app.isGlobal {
                                Button("Remove", role: .destructive) {
                                    appState.removeAppTarget(app)
                                }
                            }
                        }
                }
            }
            .listStyle(.sidebar)

            Divider()

            // Accent Color Picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Accent Color")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 5) {
                    ForEach(AccentColorChoice.allCases) { choice in
                        Circle()
                            .fill(choice.color)
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: appState.accentColorChoice == choice ? 2 : 0)
                            )
                            .shadow(color: appState.accentColorChoice == choice ? choice.color.opacity(0.6) : .clear, radius: 3)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    appState.accentColorChoice = choice
                                    UserDefaults.standard.set(choice.rawValue, forKey: "GTTAccentColor")
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct AppTargetRow: View {
    let app: AppTarget

    var body: some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: app.isGlobal ? "globe" : "app")
                    .frame(width: 20, height: 20)
            }
            Text(app.name)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}

struct AppPickerView: View {
    let onSelect: (AppTarget) -> Void
    @State private var searchText = ""
    @State private var runningApps: [AppTarget] = []

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Application")
                .font(.headline)
                .padding()

            TextField("Search apps...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            List(filteredApps) { app in
                Button(action: { onSelect(app) }) {
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 24, height: 24)
                        }
                        Text(app.name)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { loadRunningApps() }
    }

    private var filteredApps: [AppTarget] {
        if searchText.isEmpty { return runningApps }
        return runningApps.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func loadRunningApps() {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> AppTarget? in
                guard let name = app.localizedName,
                      let bundleID = app.bundleIdentifier else { return nil }
                return AppTarget(
                    id: UUID(),
                    bundleID: bundleID,
                    name: name,
                    iconPath: app.bundleURL?.path
                )
            }
            .sorted { $0.name < $1.name }
        runningApps = apps
    }
}
