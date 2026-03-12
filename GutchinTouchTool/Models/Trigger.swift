import Foundation

enum TriggerInput: Codable, Hashable {
    case trackpadGesture(TrackpadGesture)
    case keyboardShortcut(KeyboardShortcut)
    case mouseButton(MouseButton)
    case drawingPattern(String)
    case namedTrigger(String)

    var displayName: String {
        switch self {
        case .trackpadGesture(let gesture): return gesture.rawValue
        case .keyboardShortcut(let shortcut): return shortcut.displayString
        case .mouseButton(let button): return button.rawValue
        case .drawingPattern(let name): return "Drawing: \(name)"
        case .namedTrigger(let name): return name
        }
    }

    var category: TriggerCategory {
        switch self {
        case .trackpadGesture: return .trackpad
        case .keyboardShortcut: return .keyboard
        case .mouseButton: return .normalMouse
        case .drawingPattern: return .drawings
        case .namedTrigger: return .otherTriggers
        }
    }
}

struct Trigger: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var input: TriggerInput
    var actions: [TriggerAction]
    var isEnabled: Bool
    var appBundleID: String? // nil means global (All Apps)
    var order: Int

    init(name: String, input: TriggerInput, appBundleID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.input = input
        self.actions = []
        self.isEnabled = true
        self.appBundleID = appBundleID
        self.order = 0
    }

    var displayName: String {
        if name.isEmpty {
            return input.displayName
        }
        return name
    }
}
