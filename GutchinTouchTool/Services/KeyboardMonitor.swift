import Foundation
import AppKit
import Carbon

class KeyboardMonitor: ObservableObject {
    @Published var isMonitoring = false
    private var localKeyMonitor: Any?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var completionHandler: ((KeyboardShortcut) -> Void)?
    private var hasTap = false // tracks if we created a tap with a retained self

    func startRecording(completion: @escaping (KeyboardShortcut) -> Void) {
        stopRecording()
        completionHandler = completion
        isMonitoring = true

        // Local monitor for key events within our app
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isMonitoring else { return event }

            // Escape cancels recording without setting a shortcut
            if event.keyCode == 53 {
                DispatchQueue.main.async { self.stopRecording() }
                return nil
            }

            let shortcut = KeyboardShortcut(
                keyCode: event.keyCode,
                modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            )
            self.finishRecording(with: shortcut)
            return nil
        }

        // CGEventTap for system-intercepted keys (fn keys, media keys etc.)
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let retainedSelf = Unmanaged.passRetained(self)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()

            guard monitor.isMonitoring else { return Unmanaged.passRetained(event) }

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            if type == .keyDown {
                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                var modifiers: NSEvent.ModifierFlags = []
                if flags.contains(.maskCommand) { modifiers.insert(.command) }
                if flags.contains(.maskAlternate) { modifiers.insert(.option) }
                if flags.contains(.maskShift) { modifiers.insert(.shift) }
                if flags.contains(.maskControl) { modifiers.insert(.control) }

                let shortcut = KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
                DispatchQueue.main.async {
                    monitor.finishRecording(with: shortcut)
                }
                return nil // swallow
            }

            return Unmanaged.passRetained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: retainedSelf.toOpaque()
        )

        if let tap = eventTap {
            hasTap = true
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            retainedSelf.release()
            hasTap = false
        }
    }

    private func finishRecording(with shortcut: KeyboardShortcut) {
        guard isMonitoring else { return }
        let handler = completionHandler
        stopRecording()
        handler?(shortcut)
    }

    func stopRecording() {
        completionHandler = nil

        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if hasTap {
            Unmanaged<KeyboardMonitor>.passUnretained(self).release()
            hasTap = false
        }

        // Ensure UI update happens on main thread
        if Thread.isMainThread {
            isMonitoring = false
        } else {
            DispatchQueue.main.async { self.isMonitoring = false }
        }
    }

    // MARK: - Global shortcut monitoring for trigger execution

    private var globalMonitors: [Any] = []
    private var triggerEventTap: CFMachPort?
    private var triggerRunLoopSource: CFRunLoopSource?
    private var registeredTriggers: [(id: UUID, shortcut: KeyboardShortcut, actions: [TriggerAction], appBundleID: String?)] = []

    // Static reference for CGEventTap callback (C function can't capture self)
    private static var activeMonitor: KeyboardMonitor?

    func registerTriggers(_ triggers: [Trigger]) {
        unregisterAll()
        let keyboardTriggers = triggers.filter {
            if case .keyboardShortcut = $0.input { return $0.isEnabled }
            return false
        }

        for trigger in keyboardTriggers {
            if case .keyboardShortcut(let shortcut) = trigger.input {
                registeredTriggers.append((id: trigger.id, shortcut: shortcut, actions: trigger.actions, appBundleID: trigger.appBundleID))
            }
        }

        guard !registeredTriggers.isEmpty else { return }

        KeyboardMonitor.activeMonitor = self

        // Use CGEventTap to catch all key events including fn/media keys
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let monitor = KeyboardMonitor.activeMonitor else {
                return Unmanaged.passRetained(event)
            }

            // Re-enable if disabled by timeout
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.triggerEventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            // Don't intercept while recording shortcuts
            if monitor.isMonitoring {
                return Unmanaged.passRetained(event)
            }

            if type == .keyDown {
                // Skip events posted by our own ActionExecutor
                if event.getIntegerValueField(.eventSourceUserData) == 0x475454 {
                    return Unmanaged.passRetained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let cgFlags = event.flags
                var modifiers: NSEvent.ModifierFlags = []
                if cgFlags.contains(.maskCommand) { modifiers.insert(.command) }
                if cgFlags.contains(.maskAlternate) { modifiers.insert(.option) }
                if cgFlags.contains(.maskShift) { modifiers.insert(.shift) }
                if cgFlags.contains(.maskControl) { modifiers.insert(.control) }

                let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let matching = monitor.registeredTriggers.filter {
                    $0.shortcut.keyCode == keyCode && $0.shortcut.modifiers == modifiers
                }
                let appSpecific = matching.filter { $0.appBundleID != nil && $0.appBundleID == frontBundleID }
                let global = matching.filter { $0.appBundleID == nil }
                let toFire = appSpecific.isEmpty ? global : appSpecific

                if !toFire.isEmpty {
                    DispatchQueue.main.async {
                        for trigger in toFire {
                            ActionExecutor.executeActions(trigger.actions)
                            LiveTouchState.shared.flashTrigger(trigger.id)
                            NotificationCenter.default.post(name: .gestureDidFire, object: nil, userInfo: ["name": trigger.shortcut.displayString])
                        }
                    }
                    return nil // swallow the key event
                }
            }

            return Unmanaged.passRetained(event)
        }

        triggerEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        )

        if let tap = triggerEventTap {
            triggerRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = triggerRunLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            NSLog("[KeyboardMonitor] Failed to create CGEventTap for triggers — using NSEvent fallback")
            // Fallback to NSEvent monitor (won't catch fn keys)
            let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleGlobalKeyEvent(event)
            }
            if let monitor = monitor {
                globalMonitors.append(monitor)
            }
        }
    }

    private func handleGlobalKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        let matching = registeredTriggers.filter { $0.shortcut.keyCode == event.keyCode && $0.shortcut.modifiers == flags }
        let appSpecific = matching.filter { $0.appBundleID != nil && $0.appBundleID == frontBundleID }
        let global = matching.filter { $0.appBundleID == nil }

        let toFire = appSpecific.isEmpty ? global : appSpecific
        for trigger in toFire {
            ActionExecutor.executeActions(trigger.actions)
            LiveTouchState.shared.flashTrigger(trigger.id)
            NotificationCenter.default.post(name: .gestureDidFire, object: nil, userInfo: ["name": trigger.shortcut.displayString])
        }
    }

    func unregisterAll() {
        for monitor in globalMonitors {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitors.removeAll()

        if let tap = triggerEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            triggerEventTap = nil
        }
        if let source = triggerRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            triggerRunLoopSource = nil
        }
        if KeyboardMonitor.activeMonitor === self {
            KeyboardMonitor.activeMonitor = nil
        }

        registeredTriggers.removeAll()
    }

    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        unregisterAll()
    }
}
