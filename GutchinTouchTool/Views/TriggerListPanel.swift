import SwiftUI

// NSView-based double-click handler that doesn't interfere with SwiftUI single-click selection
struct DoubleClickHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> DoubleClickView {
        let view = DoubleClickView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: DoubleClickView, context: Context) {
        nsView.action = action
    }

    class DoubleClickView: NSView {
        var action: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            // Always pass through so List selection works
            super.mouseDown(with: event)
            if event.clickCount == 2 {
                action?()
            }
        }

        // Accept first mouse so clicks always reach us
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

struct TriggerListPanel: View {
    @EnvironmentObject var appState: AppState
    @State private var showingEditTrigger = false

    var body: some View {
        VStack(spacing: 0) {
            // Trigger Category Tabs
            TriggerCategoryTabBar()
                .padding(.horizontal, 8)
                .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            // Trigger List
            if appState.currentTriggers.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: appState.selectedTriggerCategory.iconName)
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No \(appState.selectedTriggerCategory.rawValue) triggers")
                        .foregroundColor(.secondary)
                    Text("Click + to add a trigger")
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: Binding(
                    get: { appState.selectedTrigger?.id },
                    set: { id in
                        appState.selectedTrigger = appState.currentTriggers.first { $0.id == id }
                        appState.selectedAction = nil
                    }
                )) {
                    ForEach(appState.currentTriggers) { trigger in
                        TriggerRow(trigger: trigger)
                            .tag(trigger.id)
                            .overlay(
                                DoubleClickHandler {
                                    appState.selectedTrigger = trigger
                                    showingEditTrigger = true
                                }
                            )
                            .contextMenu {
                                Button("Edit") {
                                    appState.selectedTrigger = trigger
                                    showingEditTrigger = true
                                }
                                Button(trigger.isEnabled ? "Disable" : "Enable") {
                                    appState.toggleTrigger(trigger)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    appState.removeTrigger(trigger)
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            // Bottom bar with add button
            HStack(spacing: 6) {
                Button(action: { appState.showingAddTrigger = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $appState.showingAddTrigger) {
                    AddTriggerSheet(keyboardMonitor: appState.keyboardMonitor)
                }

                if appState.selectedTrigger != nil {
                    Button(action: { showingEditTrigger = true }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showingEditTrigger) {
                        if let trigger = appState.selectedTrigger {
                            EditTriggerSheet(trigger: trigger)
                        }
                    }

                    Button(action: {
                        if let trigger = appState.selectedTrigger {
                            appState.removeTrigger(trigger)
                        }
                    }) {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(8)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct TriggerCategoryTabBar: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(TriggerCategory.allCases) { category in
                    Button(action: {
                        appState.selectedTriggerCategory = category
                        appState.selectedTrigger = nil
                        appState.selectedAction = nil
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 16))
                            Text(category.rawValue)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 60, minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                        .background(
                            appState.selectedTriggerCategory == category
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(
                        appState.selectedTriggerCategory == category
                            ? .accentColor
                            : .secondary
                    )
                }
            }
        }
    }
}

struct TriggerRow: View {
    let trigger: Trigger

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(trigger.isEnabled ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(trigger.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text("\(trigger.input.displayName) · \(trigger.actions.count) action\(trigger.actions.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(trigger.isEnabled ? 1 : 0.5)
    }
}

struct AddTriggerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var keyboardMonitor: KeyboardMonitor

    @State private var selectedGesture: TrackpadGesture = .twoFingerSwipeUp
    @State private var selectedMouseButton: MouseButton = .button3
    @State private var recordedShortcut: KeyboardShortcut?
    @State private var triggerName = ""
    @State private var namedTriggerName = ""
    @State private var gestureSearch = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Add New Trigger")
                .font(.headline)

            Text("Category: \(appState.selectedTriggerCategory.rawValue)")
                .foregroundColor(.secondary)

            Divider()

            switch appState.selectedTriggerCategory {
            case .trackpad:
                trackpadPicker
            case .keyboard:
                keyboardRecorder
            case .normalMouse:
                mousePicker
            case .otherTriggers:
                namedTriggerField
            default:
                Text("Coming soon for \(appState.selectedTriggerCategory.rawValue)")
                    .foregroundColor(.secondary)
            }

            TextField("Trigger Name (optional)", text: $triggerName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add") { addTrigger() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private var canAdd: Bool {
        switch appState.selectedTriggerCategory {
        case .keyboard: return recordedShortcut != nil
        case .otherTriggers: return !namedTriggerName.isEmpty
        default: return true
        }
    }

    private var filteredGestures: [TrackpadGesture] {
        if gestureSearch.isEmpty { return TrackpadGesture.allCases.map { $0 } }
        return TrackpadGesture.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(gestureSearch) }
    }

    private var trackpadPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Select Gesture:")
                .font(.subheadline)
            TextField("Search gestures...", text: $gestureSearch)
                .textFieldStyle(.roundedBorder)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredGestures) { gesture in
                            let selected = selectedGesture == gesture
                            HStack {
                                Text(gesture.rawValue)
                                    .foregroundColor(selected ? .white : .primary)
                                Spacer()
                                if selected {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected ? Color.accentColor : Color.clear)
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                selectedGesture = gesture
                                addTrigger()
                            }
                            .onTapGesture { selectedGesture = gesture }
                            .id(gesture)
                        }
                    }
                    .padding(4)
                }
                .onChange(of: gestureSearch) { _ in
                    if let first = filteredGestures.first {
                        selectedGesture = first
                        withAnimation { proxy.scrollTo(first, anchor: .top) }
                    }
                }
            }
            .frame(height: 200)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
        }
    }

    private var keyboardRecorder: some View {
        VStack(spacing: 12) {
            Text(recordedShortcut?.displayString ?? "Press a key combination...")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .frame(height: 50)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(keyboardMonitor.isMonitoring ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: 2)
                )

            Button(keyboardMonitor.isMonitoring ? "Recording..." : "Record Shortcut") {
                keyboardMonitor.startRecording { shortcut in
                    recordedShortcut = shortcut
                }
            }
            .disabled(keyboardMonitor.isMonitoring)
        }
    }

    private var mousePicker: some View {
        VStack(alignment: .leading) {
            Text("Select Mouse Button:")
                .font(.subheadline)
            Picker("Button", selection: $selectedMouseButton) {
                ForEach(MouseButton.allCases) { button in
                    Text(button.rawValue).tag(button)
                }
            }
            .labelsHidden()
        }
    }

    private var namedTriggerField: some View {
        VStack(alignment: .leading) {
            Text("Named Trigger:")
                .font(.subheadline)
            TextField("Enter trigger name", text: $namedTriggerName)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func addTrigger() {
        let input: TriggerInput
        switch appState.selectedTriggerCategory {
        case .trackpad:
            input = .trackpadGesture(selectedGesture)
        case .keyboard:
            guard let shortcut = recordedShortcut else { return }
            input = .keyboardShortcut(shortcut)
        case .normalMouse:
            input = .mouseButton(selectedMouseButton)
        case .otherTriggers:
            input = .namedTrigger(namedTriggerName)
        default:
            return
        }

        let trigger = Trigger(
            name: triggerName,
            input: input,
            appBundleID: appState.selectedAppTarget.bundleID
        )
        appState.addTrigger(trigger)
        dismiss()
    }
}

struct EditTriggerSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let trigger: Trigger
    @State private var triggerName: String = ""
    @State private var selectedGesture: TrackpadGesture = .twoFingerSwipeUp
    @State private var selectedMouseButton: MouseButton = .button3
    @State private var changeGesture = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Trigger")
                .font(.headline)

            Text("Current: \(trigger.input.displayName)")
                .foregroundColor(.secondary)

            Divider()

            TextField("Trigger Name", text: $triggerName)
                .textFieldStyle(.roundedBorder)

            // Option to change the gesture/input
            Toggle("Change gesture", isOn: $changeGesture)

            if changeGesture {
                gestureEditor
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") { saveTrigger() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            triggerName = trigger.name
            // Pre-select current gesture if applicable
            if case .trackpadGesture(let g) = trigger.input {
                selectedGesture = g
            }
            if case .mouseButton(let b) = trigger.input {
                selectedMouseButton = b
            }
        }
    }

    @ViewBuilder
    private var gestureEditor: some View {
        switch trigger.input.category {
        case .trackpad:
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(TrackpadGesture.allCases) { gesture in
                        let selected = selectedGesture == gesture
                        HStack {
                            Text(gesture.rawValue)
                                .foregroundColor(selected ? .white : .primary)
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selected ? Color.accentColor : Color.clear)
                        .cornerRadius(4)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedGesture = gesture }
                    }
                }
                .padding(4)
            }
            .frame(height: 180)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
        case .normalMouse:
            Picker("Button", selection: $selectedMouseButton) {
                ForEach(MouseButton.allCases) { button in
                    Text(button.rawValue).tag(button)
                }
            }
            .labelsHidden()
        default:
            Text("Cannot change this input type here")
                .foregroundColor(.secondary)
        }
    }

    private func saveTrigger() {
        var updated = trigger
        updated.name = triggerName

        if changeGesture {
            switch trigger.input.category {
            case .trackpad:
                updated.input = .trackpadGesture(selectedGesture)
            case .normalMouse:
                updated.input = .mouseButton(selectedMouseButton)
            default:
                break
            }
        }

        appState.updateTrigger(updated)
        dismiss()
    }
}
