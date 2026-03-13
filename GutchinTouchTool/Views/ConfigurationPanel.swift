import SwiftUI

struct ConfigurationPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Configuration")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    if let action = appState.selectedAction, let trigger = appState.selectedTrigger {
                        ActionConfigView(keyboardMonitor: appState.keyboardMonitor, trigger: trigger, action: action)
                    } else if let trigger = appState.selectedTrigger {
                        TriggerConfigView(trigger: trigger)
                    } else {
                        emptyState
                    }
                }
                .padding(16)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("Select a trigger or action to configure")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TriggerConfigView: View {
    @EnvironmentObject var appState: AppState
    let trigger: Trigger

    @State private var name: String
    @State private var isEnabled: Bool
    @AppStorage("GTTPressDragThreshold") private var pressDragThreshold: Double = 300
    @AppStorage("GTTTipTapMinRestTime") private var tipTapMinRestTime: Double = 0.12

    init(trigger: Trigger) {
        self.trigger = trigger
        _name = State(initialValue: trigger.name)
        _isEnabled = State(initialValue: trigger.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Trigger Settings") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Type:")
                            .foregroundColor(.secondary)
                        Text(trigger.input.category.rawValue)
                            .fontWeight(.medium)
                    }

                    HStack {
                        Text("Input:")
                            .foregroundColor(.secondary)
                        Text(trigger.input.displayName)
                            .fontWeight(.medium)
                            .font(.system(.body, design: .monospaced))
                    }

                    Divider()

                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: name) { _, newValue in
                            var updated = trigger
                            updated.name = newValue
                            appState.updateTrigger(updated)
                        }

                    Toggle("Enabled", isOn: $isEnabled)
                        .onChange(of: isEnabled) { _, newValue in
                            var updated = trigger
                            updated.isEnabled = newValue
                            appState.updateTrigger(updated)
                        }
                }
                .padding(8)
            }

            GroupBox("Scope") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: trigger.appBundleID == nil ? "globe" : "app")
                        Text(trigger.appBundleID == nil ? "Global (All Apps)" : trigger.appBundleID!)
                    }
                    .padding(8)
                }
            }

            GroupBox("Actions (\(trigger.actions.count))") {
                VStack(alignment: .leading, spacing: 4) {
                    if trigger.actions.isEmpty {
                        Text("No actions assigned")
                            .foregroundColor(.secondary)
                            .padding(8)
                    } else {
                        ForEach(trigger.actions) { action in
                            HStack {
                                Image(systemName: action.actionType.iconName)
                                    .foregroundColor(.accentColor)
                                Text(action.actionType.rawValue)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }

            // Gesture animation preview
            if case .trackpadGesture(let gesture) = trigger.input {
                GesturePreviewView(gesture: gesture)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                // TipTap sensitivity slider
                if gesture == .tipTapLeft || gesture == .tipTapRight || gesture == .tipTapMiddle {
                    GroupBox("TipTap Sensitivity") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Min. rest time:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(tipTapMinRestTime * 1000)) ms")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.accentColor)
                            }
                            Slider(value: $tipTapMinRestTime, in: 0.02...0.4, step: 0.01)
                            HStack {
                                Text("Sensitive")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Fewer false positives")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                    }
                }

                // Press-drag sensitivity slider
                if gesture == .twoFingerPressDragLeft || gesture == .twoFingerPressDragRight {
                    GroupBox("Press-Drag Sensitivity") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Min. drag distance:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int(pressDragThreshold)) pt")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.accentColor)
                            }
                            Slider(value: $pressDragThreshold, in: 10...600, step: 10)
                            HStack {
                                Text("Sensitive")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("Long swipe")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                    }
                }
            }

            Spacer()
        }
    }
}

struct ActionConfigView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var keyboardMonitor: KeyboardMonitor
    let trigger: Trigger
    let action: TriggerAction

    @State private var isEnabled: Bool
    @State private var text: String
    @State private var scriptContent: String
    @State private var url: String
    @State private var applicationName: String
    @State private var delayMs: String
    @State private var recordedShortcut: KeyboardShortcut?
    @EnvironmentObject private var state: AppState

    init(keyboardMonitor: KeyboardMonitor, trigger: Trigger, action: TriggerAction) {
        self.keyboardMonitor = keyboardMonitor
        self.trigger = trigger
        self.action = action
        _isEnabled = State(initialValue: action.isEnabled)
        _text = State(initialValue: action.parameters.text ?? "")
        _scriptContent = State(initialValue: action.parameters.scriptContent ?? "")
        _url = State(initialValue: action.parameters.url ?? "")
        if let keyCode = action.parameters.shortcutKeyCode {
            let mods = NSEvent.ModifierFlags(rawValue: action.parameters.shortcutModifiers ?? 0)
            _recordedShortcut = State(initialValue: KeyboardShortcut(keyCode: keyCode, modifiers: mods))
        } else {
            _recordedShortcut = State(initialValue: nil)
        }
        _applicationName = State(initialValue: action.parameters.applicationName ?? "")
        _delayMs = State(initialValue: action.parameters.delayBeforeMs.map(String.init) ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Action: \(action.actionType.rawValue)") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: action.actionType.iconName)
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text(action.actionType.rawValue)
                            .font(.headline)
                    }

                    Divider()

                    Toggle("Enabled", isOn: $isEnabled)
                        .onChange(of: isEnabled) { _, newValue in
                            saveAction { $0.isEnabled = newValue }
                        }
                }
                .padding(8)
            }

            // Action-specific parameters
            switch action.actionType {
            case .typeText:
                GroupBox("Text to Type") {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                        .onChange(of: text) { _, newValue in
                            saveAction { $0.parameters.text = newValue }
                        }
                        .padding(4)
                }

            case .runAppleScript, .runShellScript:
                GroupBox(action.actionType == .runAppleScript ? "AppleScript" : "Shell Script") {
                    TextEditor(text: $scriptContent)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .onChange(of: scriptContent) { _, newValue in
                            saveAction { $0.parameters.scriptContent = newValue }
                        }
                        .padding(4)
                }

            case .openURL:
                GroupBox("URL") {
                    TextField("https://...", text: $url)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: url) { _, newValue in
                            saveAction { $0.parameters.url = newValue }
                        }
                        .padding(8)
                }

            case .launchApplication, .quitApplication, .hideApplication, .toggleApplication:
                GroupBox("Application") {
                    TextField("Application name or bundle ID", text: $applicationName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: applicationName) { _, newValue in
                            saveAction { $0.parameters.applicationName = newValue }
                        }
                        .padding(8)
                }

            case .sendKeyStroke:
                GroupBox("Keyboard Shortcut to Send") {
                    let monitoring = keyboardMonitor.isMonitoring
                    VStack(spacing: 12) {
                        // Display box
                        ZStack {
                            if monitoring {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 10, height: 10)
                                        .overlay(
                                            Circle()
                                                .fill(.red.opacity(0.4))
                                                .frame(width: 18, height: 18)
                                                .scaleEffect(monitoring ? 1.3 : 1.0)
                                                .opacity(monitoring ? 0 : 1)
                                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: monitoring)
                                        )
                                    Text("RECORDING — press any key...")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.red)
                                }
                            } else if let shortcut = recordedShortcut {
                                Text(shortcut.displayString)
                                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            } else {
                                Text("No shortcut set")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(height: 56)
                        .frame(maxWidth: .infinity)
                        .background(
                            monitoring
                                ? Color.red.opacity(0.08)
                                : Color(nsColor: .textBackgroundColor)
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    monitoring ? Color.red : Color.gray.opacity(0.3),
                                    lineWidth: monitoring ? 2 : 1
                                )
                        )
                        .animation(.easeInOut(duration: 0.2), value: monitoring)

                        // Buttons
                        HStack(spacing: 12) {
                            if monitoring {
                                Button(action: {
                                    keyboardMonitor.stopRecording()
                                }) {
                                    HStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(.white)
                                            .frame(width: 10, height: 10)
                                        Text("Stop")
                                    }
                                    .frame(minWidth: 100)
                                    .padding(.vertical, 4)
                                }
                                .keyboardShortcut(.escape, modifiers: [])
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            } else {
                                Button(action: {
                                    keyboardMonitor.startRecording { shortcut in
                                        recordedShortcut = shortcut
                                        saveAction {
                                            $0.parameters.shortcutKeyCode = shortcut.keyCode
                                            $0.parameters.shortcutModifiers = shortcut.modifiers.rawValue
                                        }
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(.red)
                                            .frame(width: 10, height: 10)
                                        Text("Record Shortcut")
                                            .lineLimit(1)
                                            .fixedSize()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.bordered)
                            }

                            if recordedShortcut != nil && !monitoring {
                                Button(action: {
                                    recordedShortcut = nil
                                    saveAction {
                                        $0.parameters.shortcutKeyCode = nil
                                        $0.parameters.shortcutModifiers = nil
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark.circle")
                                        Text("Clear")
                                    }
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(8)
                }

            default:
                GroupBox("Info") {
                    Text("This action requires no additional configuration.")
                        .foregroundColor(.secondary)
                        .padding(8)
                }
            }

            GroupBox("Timing") {
                HStack {
                    Text("Delay before (ms):")
                    TextField("0", text: $delayMs)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .onChange(of: delayMs) { _, newValue in
                            saveAction { $0.parameters.delayBeforeMs = Int(newValue) }
                        }
                }
                .padding(8)
            }

            // Test button
            Button(action: {
                ActionExecutor.executeAction(action)
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Test Action")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    private func saveAction(_ modify: (inout TriggerAction) -> Void) {
        var updated = action
        modify(&updated)
        appState.updateAction(in: trigger, action: updated)
    }
}
