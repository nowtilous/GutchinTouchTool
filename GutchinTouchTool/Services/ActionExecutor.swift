import Foundation
import AppKit

class ActionExecutor {
    // Hook for testing — when set, actions call this instead of performing real work
    static var onActionExecuted: ((TriggerAction) -> Void)?

    // Track the last non-self frontmost app so we can target it when our app is in front
    private static var lastExternalApp: NSRunningApplication?
    private static var workspaceObserver: Any?

    static func startTrackingFrontApp() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != Bundle.main.bundleIdentifier {
                lastExternalApp = app
            }
        }
        // Initialize with current frontmost if it's not us
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = front
        }
    }

    static func executeActions(_ actions: [TriggerAction]) {
        for action in actions where action.isEnabled {
            if let delay = action.parameters.delayBeforeMs, delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(delay) / 1000.0) {
                    executeAction(action)
                }
            } else {
                executeAction(action)
            }
        }
    }

    static func executeAction(_ action: TriggerAction) {
        NSLog("[ActionExecutor] Executing: %@", action.actionType.rawValue)
        GestureLog.shared.logFromAnyThread("Executing: \(action.actionType.rawValue)\(actionDetail(action))", level: .action)

        // If test hook is set, call it and return
        if let hook = onActionExecuted {
            hook(action)
            return
        }

        switch action.actionType {
        // Window Management
        case .maximizeWindow:
            WindowManager.shared.maximizeWindow()
        case .minimizeWindow:
            WindowManager.shared.minimizeWindow()
        case .snapWindowLeft:
            WindowManager.shared.snapWindow(.left)
        case .snapWindowRight:
            WindowManager.shared.snapWindow(.right)
        case .snapWindowTopLeft:
            WindowManager.shared.snapWindow(.topLeft)
        case .snapWindowTopRight:
            WindowManager.shared.snapWindow(.topRight)
        case .snapWindowBottomLeft:
            WindowManager.shared.snapWindow(.bottomLeft)
        case .snapWindowBottomRight:
            WindowManager.shared.snapWindow(.bottomRight)
        case .centerWindow:
            WindowManager.shared.centerWindow()
        case .moveWindowNextMonitor:
            WindowManager.shared.moveToNextMonitor()
        case .restoreWindowSize:
            WindowManager.shared.restoreWindow()

        // Keyboard
        case .sendKeyStroke:
            if let keyCode = action.parameters.shortcutKeyCode {
                let flags = NSEvent.ModifierFlags(rawValue: action.parameters.shortcutModifiers ?? 0)
                sendKeyStroke(keyCode: keyCode, flags: flags)
            }
        case .typeText:
            if let text = action.parameters.text {
                typeText(text)
            }

        // Application Control
        case .launchApplication:
            if let path = action.parameters.applicationPath {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } else if let name = action.parameters.applicationName {
                NSWorkspace.shared.launchApplication(name)
            }
        case .quitApplication:
            if let name = action.parameters.applicationName {
                let apps = NSRunningApplication.runningApplications(withBundleIdentifier: name)
                apps.forEach { $0.terminate() }
            }
        case .hideApplication:
            if let name = action.parameters.applicationName {
                let apps = NSRunningApplication.runningApplications(withBundleIdentifier: name)
                apps.forEach { $0.hide() }
            }
        case .toggleApplication:
            if let name = action.parameters.applicationName {
                let apps = NSRunningApplication.runningApplications(withBundleIdentifier: name)
                if let app = apps.first {
                    if app.isHidden { app.unhide() } else { app.hide() }
                } else {
                    NSWorkspace.shared.launchApplication(name)
                }
            }

        // System Actions
        case .sleepComputer:
            let task = Process()
            task.launchPath = "/usr/bin/pmset"
            task.arguments = ["sleepnow"]
            try? task.run()
        case .lockScreen:
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = ["-a", "/System/Library/CoreServices/ScreenSaverEngine.app"]
            try? task.run()
        case .toggleDarkMode:
            runAppleScript("""
                tell application "System Events"
                    tell appearance preferences
                        set dark mode to not dark mode
                    end tell
                end tell
            """)
        case .toggleDoNotDisturb:
            break
        case .volumeUp:
            sendMediaKey(keyCode: NX_KEYTYPE_SOUND_UP)
        case .volumeDown:
            sendMediaKey(keyCode: NX_KEYTYPE_SOUND_DOWN)
        case .muteVolume:
            sendMediaKey(keyCode: NX_KEYTYPE_MUTE)
        case .brightnessUp:
            sendMediaKey(keyCode: NX_KEYTYPE_BRIGHTNESS_UP)
        case .brightnessDown:
            sendMediaKey(keyCode: NX_KEYTYPE_BRIGHTNESS_DOWN)

        // Script Execution
        case .runAppleScript:
            if let script = action.parameters.scriptContent {
                runAppleScript(script)
            }
        case .runShellScript:
            if let script = action.parameters.scriptContent {
                runShellScript(script)
            }
        case .openURL:
            if let urlString = action.parameters.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        // Media Controls
        case .playPause:
            sendMediaKey(keyCode: NX_KEYTYPE_PLAY)
        case .nextTrack:
            sendMediaKey(keyCode: NX_KEYTYPE_NEXT)
        case .previousTrack:
            sendMediaKey(keyCode: NX_KEYTYPE_PREVIOUS)
        }
    }

    // MARK: - Key Stroke Sending (tries multiple strategies)

    private static func sendKeyStroke(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        GestureLog.shared.logFromAnyThread("sendKeyStroke keyCode=\(keyCode) mods=\(flags.rawValue)", level: .action)

        sendViaCGEvent(keyCode: keyCode, flags: flags, tapPoint: .cgSessionEventTap, label: "cgSessionEventTap")
    }

    private static func sendViaOsascript(keyCode: UInt16, flags: NSEvent.ModifierFlags) {
        var usingParts: [String] = []
        if flags.contains(.command) { usingParts.append("command down") }
        if flags.contains(.option) { usingParts.append("option down") }
        if flags.contains(.shift) { usingParts.append("shift down") }
        if flags.contains(.control) { usingParts.append("control down") }

        let keyChar = keyCodeToCharacter(keyCode)
        let usingClause = usingParts.isEmpty ? "" : " using {\(usingParts.joined(separator: ", "))}"

        let script: String
        if let char = keyChar {
            script = "tell application \"System Events\" to keystroke \"\(char)\"\(usingClause)"
        } else {
            script = "tell application \"System Events\" to key code \(keyCode)\(usingClause)"
        }

        GestureLog.shared.logFromAnyThread("osascript: \(script)", level: .action)

        DispatchQueue.global(qos: .userInteractive).async {
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            do {
                try task.run()
                task.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if task.terminationStatus == 0 {
                    GestureLog.shared.logFromAnyThread("osascript OK", level: .fire)
                } else {
                    GestureLog.shared.logFromAnyThread("osascript FAIL: \(output)", level: .error)
                }
            } catch {
                GestureLog.shared.logFromAnyThread("osascript error: \(error.localizedDescription)", level: .error)
            }
        }
    }

    private static func sendViaCGEvent(keyCode: UInt16, flags: NSEvent.ModifierFlags, tapPoint: CGEventTapLocation, label: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            GestureLog.shared.logFromAnyThread("CGEvent[\(label)] creation failed", level: .error)
            return
        }

        var cgFlags = CGEventFlags()
        if flags.contains(.command) { cgFlags.insert(.maskCommand) }
        if flags.contains(.option) { cgFlags.insert(.maskAlternate) }
        if flags.contains(.shift) { cgFlags.insert(.maskShift) }
        if flags.contains(.control) { cgFlags.insert(.maskControl) }

        // Add fn flag for function keys (F1-F15) — required on Mac laptops
        let fnKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113]
        if fnKeyCodes.contains(keyCode) {
            cgFlags.insert(.maskSecondaryFn)
        }

        keyDown.flags = cgFlags
        keyUp.flags = cgFlags

        // Tag events so our own CGEventTap in KeyboardMonitor skips them
        let selfTag = Int64(0x475454) // "GTT"
        keyDown.setIntegerValueField(.eventSourceUserData, value: selfTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: selfTag)

        // If our app is frontmost, activate the last known external app first
        // so the keystroke reaches the app the user was actually working in
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier == Bundle.main.bundleIdentifier,
           let target = lastExternalApp, !target.isTerminated {
            GestureLog.shared.logFromAnyThread("CGEvent[\(label)] activating \(target.localizedName ?? "?") before posting", level: .action)
            target.activate()
            usleep(100000) // 100ms for activation to take effect
        }

        keyDown.post(tap: tapPoint)
        usleep(20000)
        keyUp.post(tap: tapPoint)
        GestureLog.shared.logFromAnyThread("CGEvent[\(label)] posted keyCode=\(keyCode)", level: .fire)
    }

    private static func keyCodeToCharacter(_ keyCode: UInt16) -> String? {
        let mapping: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
            8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
            16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
            37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "n", 46: "m", 47: ".", 49: " "
        ]
        return mapping[keyCode]
    }

    // MARK: - Other helpers

    private static func typeText(_ text: String) {
        for char in text {
            let source = CGEventSource(stateID: .hidSystemState)
            let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            var utf16 = Array(String(char).utf16)
            event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            event?.post(tap: .cghidEventTap)

            let upEvent = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            upEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func runAppleScript(_ script: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    NSLog("[ActionExecutor] AppleScript error: %@", "\(error)")
                }
            }
        }
    }

    private static func runShellScript(_ script: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/bin/zsh"
            task.arguments = ["-c", script]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            try? task.run()
            task.waitUntilExit()
        }
    }

    private static func sendMediaKey(keyCode: Int32) {
        func doKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: (down ? 0xa00 : 0xb00))
            let data1 = Int((keyCode << 16) | (down ? 0xa00 : 0xb00))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        doKey(down: true)
        doKey(down: false)
    }

    private static func actionDetail(_ action: TriggerAction) -> String {
        let p = action.parameters
        switch action.actionType {
        case .sendKeyStroke:
            guard let keyCode = p.shortcutKeyCode else { return "" }
            var parts: [String] = []
            let mods = NSEvent.ModifierFlags(rawValue: p.shortcutModifiers ?? 0)
            if mods.contains(.command) { parts.append("⌘") }
            if mods.contains(.option) { parts.append("⌥") }
            if mods.contains(.shift) { parts.append("⇧") }
            if mods.contains(.control) { parts.append("⌃") }
            let key = keyCodeToCharacter(keyCode)?.uppercased() ?? "key\(keyCode)"
            parts.append(key)
            return " [\(parts.joined())]"
        case .typeText:
            if let text = p.text { return " [\"\(text.prefix(20))\"]" }
            return ""
        case .launchApplication, .quitApplication, .hideApplication, .toggleApplication:
            return " [\(p.applicationName ?? p.applicationPath ?? "?")]"
        case .runAppleScript, .runShellScript:
            if let s = p.scriptContent { return " [\(s.prefix(30))...]" }
            return ""
        case .openURL:
            if let u = p.url { return " [\(u.prefix(40))]" }
            return ""
        default:
            return ""
        }
    }
}
