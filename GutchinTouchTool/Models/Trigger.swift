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
    var suppressClick: Bool

    init(name: String, input: TriggerInput, appBundleID: String? = nil) {
        self.id = UUID()
        self.name = name
        self.input = input
        self.actions = []
        self.isEnabled = true
        self.appBundleID = appBundleID
        self.order = 0
        self.suppressClick = false
    }

    enum CodingKeys: String, CodingKey {
        case id, name, input, actions, isEnabled, appBundleID, order, suppressClick
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        input = try container.decode(TriggerInput.self, forKey: .input)
        actions = try container.decode([TriggerAction].self, forKey: .actions)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        appBundleID = try container.decodeIfPresent(String.self, forKey: .appBundleID)
        order = try container.decode(Int.self, forKey: .order)
        suppressClick = try container.decodeIfPresent(Bool.self, forKey: .suppressClick) ?? false
    }

    var displayName: String {
        if name.isEmpty {
            return input.displayName
        }
        return name
    }
}
