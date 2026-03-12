import SwiftUI

struct ActionListPanel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Actions")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Spacer()
                if let trigger = appState.selectedTrigger {
                    Text(trigger.displayName)
                        .font(.caption)
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let trigger = appState.selectedTrigger {
                if trigger.actions.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No actions configured")
                            .foregroundColor(.secondary)
                        Text("Click + to add an action")
                            .font(.caption)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    List(selection: Binding(
                        get: { appState.selectedAction?.id },
                        set: { id in
                            appState.selectedAction = trigger.actions.first { $0.id == id }
                        }
                    )) {
                        ForEach(trigger.actions) { action in
                            ActionRow(action: action)
                                .tag(action.id)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        appState.removeAction(from: trigger, action: action)
                                    }
                                }
                        }
                        .onMove { source, destination in
                            appState.moveActions(in: trigger, from: source, to: destination)
                        }
                    }
                    .listStyle(.inset)
                }

                Divider()

                // Bottom bar
                HStack(spacing: 6) {
                    Button(action: { appState.showingAddAction = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $appState.showingAddAction) {
                        AddActionSheet()
                    }

                    if let action = appState.selectedAction {
                        Button(action: {
                            appState.removeAction(from: trigger, action: action)
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
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Select a trigger")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct ActionRow: View {
    let action: TriggerAction

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: action.actionType.iconName)
                .frame(width: 20)
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.actionType.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                if let detail = actionDetail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !action.isEnabled {
                Image(systemName: "eye.slash")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
        .opacity(action.isEnabled ? 1 : 0.5)
    }

    private var actionDetail: String? {
        switch action.actionType {
        case .typeText: return action.parameters.text
        case .runAppleScript, .runShellScript: return action.parameters.scriptContent?.prefix(50).description
        case .launchApplication, .quitApplication, .hideApplication, .toggleApplication:
            return action.parameters.applicationName
        case .openURL: return action.parameters.url
        default: return nil
        }
    }
}

struct AddActionSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: ActionCategory = .windowManagement
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            Text("Add Action")
                .font(.headline)
                .padding()

            TextField("Search actions...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            HSplitView {
                // Category list
                List(ActionCategory.allCases, selection: $selectedCategory) { category in
                    Label(category.rawValue, systemImage: category.iconName)
                        .tag(category)
                }
                .listStyle(.sidebar)
                .frame(width: 180)

                // Action list for selected category
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredActions) { actionType in
                            HStack {
                                Image(systemName: actionType.iconName)
                                    .frame(width: 24)
                                    .foregroundColor(.accentColor)
                                Text(actionType.rawValue)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.clear)
                            .cornerRadius(4)
                            .contentShape(Rectangle())
                            .onTapGesture { addAction(actionType) }
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.pointingHand.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                        }
                    }
                    .padding(4)
                }
            }
            .frame(height: 350)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding()
        }
        .frame(width: 550)
    }

    private var filteredActions: [ActionType] {
        if searchText.isEmpty {
            return ActionType.actionsForCategory(selectedCategory)
        }
        // Search across ALL categories when there's a search query
        return ActionType.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(searchText) }
    }

    private func addAction(_ actionType: ActionType) {
        guard let trigger = appState.selectedTrigger else { return }
        let action = TriggerAction(actionType: actionType)
        appState.addAction(to: trigger, action: action)
        dismiss()
    }
}
