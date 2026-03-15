import Foundation
import SwiftUI
import Combine

enum AccentColorChoice: String, CaseIterable, Identifiable {
    case blue, purple, pink, red, orange, yellow, green, cyan
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .cyan: return .cyan
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var currentPreset: Preset
    @Published var selectedAppTarget: AppTarget
    @Published var selectedTriggerCategory: TriggerCategory = .trackpad
    @Published var selectedTrigger: Trigger?
    @Published var selectedAction: TriggerAction?
    @Published var isRecordingShortcut: Bool = false
    @Published var showingAddTrigger: Bool = false
    @Published var showingAddAction: Bool = false
    @Published var showingAddApp: Bool = false
    @Published var showStatistics: Bool = false
    @Published var globalEnabled: Bool = UserDefaults.standard.object(forKey: "GTTGlobalEnabled") as? Bool ?? true
    @Published var accentColorChoice: AccentColorChoice = {
        if let raw = UserDefaults.standard.string(forKey: "GTTAccentColor"),
           let choice = AccentColorChoice(rawValue: raw) {
            return choice
        }
        return .blue
    }()

    private let presetManager = PresetManager()
    let keyboardMonitor = KeyboardMonitor()
    private let trackpadMonitor = TrackpadMonitor()
    let updateChecker = UpdateChecker()

    init() {
        let preset = PresetManager.loadPreset() ?? Preset(name: "Master Preset", isMaster: true)
        self.currentPreset = preset
        self.selectedAppTarget = preset.appTargets.first ?? .allApps
        NSLog("[GTT] Loaded preset with %d triggers", preset.triggers.count)
        // Schedule monitor start for next runloop iteration (self must be fully initialized first)
        // Skip automatic monitoring when running inside the unit-test host
        guard NSClassFromString("XCTestCase") == nil else { return }
        DispatchQueue.main.async {
            self.startMonitoring()
            self.updateChecker.startPeriodicChecks()
        }
    }

    func startMonitoring() {
        NSLog("[GTT] startMonitoring called")
        refreshMonitors()
    }

    var currentTriggers: [Trigger] {
        currentPreset.triggers(for: selectedAppTarget, category: selectedTriggerCategory)
    }

    // MARK: - App Target Management

    func addAppTarget(_ app: AppTarget) {
        if !currentPreset.appTargets.contains(where: { $0.bundleID == app.bundleID }) {
            currentPreset.appTargets.append(app)
            save()
        }
    }

    func removeAppTarget(_ app: AppTarget) {
        guard !app.isGlobal else { return }
        currentPreset.appTargets.removeAll { $0.id == app.id }
        currentPreset.triggers.removeAll { $0.appBundleID == app.bundleID }
        if selectedAppTarget.id == app.id {
            selectedAppTarget = .allApps
        }
        save()
    }

    // MARK: - Trigger Management

    func addTrigger(_ trigger: Trigger) {
        currentPreset.addTrigger(trigger)
        selectedTrigger = trigger
        save()
    }

    func removeTrigger(_ trigger: Trigger) {
        currentPreset.removeTrigger(id: trigger.id)
        if selectedTrigger?.id == trigger.id {
            selectedTrigger = nil
            selectedAction = nil
        }
        save()
    }

    func updateTrigger(_ trigger: Trigger) {
        currentPreset.updateTrigger(trigger)
        selectedTrigger = trigger
        save()
    }

    func toggleTrigger(_ trigger: Trigger) {
        var updated = trigger
        updated.isEnabled.toggle()
        updateTrigger(updated)
    }

    // MARK: - Action Management

    func addAction(to trigger: Trigger, action: TriggerAction) {
        var updated = trigger
        updated.actions.append(action)
        updateTrigger(updated)
        selectedAction = action
    }

    func removeAction(from trigger: Trigger, action: TriggerAction) {
        var updated = trigger
        updated.actions.removeAll { $0.id == action.id }
        updateTrigger(updated)
        if selectedAction?.id == action.id {
            selectedAction = nil
        }
    }

    func updateAction(in trigger: Trigger, action: TriggerAction) {
        var updated = trigger
        if let index = updated.actions.firstIndex(where: { $0.id == action.id }) {
            updated.actions[index] = action
        }
        updateTrigger(updated)
        selectedAction = action
    }

    func moveActions(in trigger: Trigger, from source: IndexSet, to destination: Int) {
        var updated = trigger
        updated.actions.move(fromOffsets: source, toOffset: destination)
        updateTrigger(updated)
    }

    // MARK: - Monitor Registration

    func toggleGlobalEnabled() {
        globalEnabled.toggle()
        UserDefaults.standard.set(globalEnabled, forKey: "GTTGlobalEnabled")
        refreshMonitors()
    }

    func refreshMonitors() {
        let allTriggers = currentPreset.triggers.filter { $0.isEnabled }
        NSLog("[GTT] Refreshing monitors with %d enabled triggers (global: %@)", allTriggers.count, globalEnabled ? "ON" : "OFF")
        keyboardMonitor.registerTriggers(allTriggers)
        trackpadMonitor.registerTriggers(allTriggers)
    }

    // MARK: - Persistence

    func save() {
        presetManager.save(currentPreset)
        refreshMonitors()
    }

    func exportPreset(to url: URL) {
        presetManager.exportPreset(currentPreset, to: url)
    }

    func importPreset(from url: URL) {
        if let preset = presetManager.importPreset(from: url) {
            currentPreset = preset
            presetManager.save(preset)
            selectedAppTarget = preset.appTargets.first ?? .allApps
            selectedTrigger = nil
            selectedAction = nil
        }
    }
}
