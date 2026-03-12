import Foundation

enum ActionCategory: String, CaseIterable, Identifiable, Codable {
    case windowManagement = "Window Management"
    case keyboardActions = "Keyboard"
    case applicationControl = "Application Control"
    case systemActions = "System Actions"
    case scriptExecution = "Script Execution"
    case mediaControls = "Media Controls"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .windowManagement: return "macwindow.on.rectangle"
        case .keyboardActions: return "keyboard"
        case .applicationControl: return "app.badge"
        case .systemActions: return "gearshape"
        case .scriptExecution: return "terminal"
        case .mediaControls: return "play.circle"
        }
    }
}

enum ActionType: String, Codable, Identifiable, CaseIterable {
    // Window Management
    case maximizeWindow = "Maximize Window"
    case minimizeWindow = "Minimize Window"
    case snapWindowLeft = "Snap Window Left Half"
    case snapWindowRight = "Snap Window Right Half"
    case snapWindowTopLeft = "Snap Window Top Left"
    case snapWindowTopRight = "Snap Window Top Right"
    case snapWindowBottomLeft = "Snap Window Bottom Left"
    case snapWindowBottomRight = "Snap Window Bottom Right"
    case centerWindow = "Center Window"
    case moveWindowNextMonitor = "Move Window to Next Monitor"
    case restoreWindowSize = "Restore Window Size"

    // Keyboard Actions
    case sendKeyStroke = "Send Keyboard Shortcut"
    case typeText = "Type Text"

    // Application Control
    case launchApplication = "Launch Application"
    case quitApplication = "Quit Application"
    case hideApplication = "Hide Application"
    case toggleApplication = "Toggle Application"

    // System Actions
    case sleepComputer = "Sleep Computer"
    case lockScreen = "Lock Screen"
    case toggleDarkMode = "Toggle Dark Mode"
    case toggleDoNotDisturb = "Toggle Do Not Disturb"
    case volumeUp = "Volume Up"
    case volumeDown = "Volume Down"
    case brightnessUp = "Brightness Up"
    case brightnessDown = "Brightness Down"
    case muteVolume = "Mute/Unmute"

    // Script Execution
    case runAppleScript = "Run AppleScript"
    case runShellScript = "Run Shell Script"
    case openURL = "Open URL"

    // Media Controls
    case playPause = "Play/Pause"
    case nextTrack = "Next Track"
    case previousTrack = "Previous Track"

    var id: String { rawValue }

    var category: ActionCategory {
        switch self {
        case .maximizeWindow, .minimizeWindow, .snapWindowLeft, .snapWindowRight,
             .snapWindowTopLeft, .snapWindowTopRight, .snapWindowBottomLeft,
             .snapWindowBottomRight, .centerWindow, .moveWindowNextMonitor,
             .restoreWindowSize:
            return .windowManagement
        case .sendKeyStroke, .typeText:
            return .keyboardActions
        case .launchApplication, .quitApplication, .hideApplication, .toggleApplication:
            return .applicationControl
        case .sleepComputer, .lockScreen, .toggleDarkMode, .toggleDoNotDisturb,
             .volumeUp, .volumeDown, .brightnessUp, .brightnessDown, .muteVolume:
            return .systemActions
        case .runAppleScript, .runShellScript, .openURL:
            return .scriptExecution
        case .playPause, .nextTrack, .previousTrack:
            return .mediaControls
        }
    }

    var iconName: String {
        switch self {
        case .maximizeWindow: return "arrow.up.left.and.arrow.down.right"
        case .minimizeWindow: return "arrow.down.right.and.arrow.up.left"
        case .snapWindowLeft: return "rectangle.lefthalf.filled"
        case .snapWindowRight: return "rectangle.righthalf.filled"
        case .snapWindowTopLeft: return "rectangle.topleft.filled"
        case .snapWindowTopRight: return "rectangle.topright.filled"
        case .snapWindowBottomLeft: return "rectangle.bottomleft.filled"
        case .snapWindowBottomRight: return "rectangle.bottomright.filled"
        case .centerWindow: return "rectangle.center.inset.filled"
        case .moveWindowNextMonitor: return "display.2"
        case .restoreWindowSize: return "arrow.uturn.backward"
        case .sendKeyStroke: return "command"
        case .typeText: return "text.cursor"
        case .launchApplication: return "app"
        case .quitApplication: return "xmark.app"
        case .hideApplication: return "eye.slash"
        case .toggleApplication: return "app.badge.checkmark"
        case .sleepComputer: return "moon"
        case .lockScreen: return "lock"
        case .toggleDarkMode: return "circle.lefthalf.filled"
        case .toggleDoNotDisturb: return "moon.circle"
        case .volumeUp: return "speaker.plus"
        case .volumeDown: return "speaker.minus"
        case .brightnessUp: return "sun.max"
        case .brightnessDown: return "sun.min"
        case .muteVolume: return "speaker.slash"
        case .runAppleScript: return "applescript"
        case .runShellScript: return "terminal"
        case .openURL: return "link"
        case .playPause: return "playpause"
        case .nextTrack: return "forward.end"
        case .previousTrack: return "backward.end"
        }
    }

    static func actionsForCategory(_ category: ActionCategory) -> [ActionType] {
        allCases.filter { $0.category == category }
    }
}

struct TriggerAction: Identifiable, Codable, Hashable {
    let id: UUID
    var actionType: ActionType
    var isEnabled: Bool
    var parameters: ActionParameters

    init(actionType: ActionType, parameters: ActionParameters = ActionParameters()) {
        self.id = UUID()
        self.actionType = actionType
        self.isEnabled = true
        self.parameters = parameters
    }
}

struct ActionParameters: Codable, Hashable {
    var text: String?
    var applicationPath: String?
    var applicationName: String?
    var scriptContent: String?
    var url: String?
    var shortcutKeyCode: UInt16?
    var shortcutModifiers: UInt?
    var delayBeforeMs: Int?

    init() {}
}
