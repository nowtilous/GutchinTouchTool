import Foundation
import AppKit

class MouseButtonMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var registeredTriggers: [(id: UUID, button: MouseButton, actions: [TriggerAction], appBundleID: String?, suppressClick: Bool)] = []

    private static var activeMonitor: MouseButtonMonitor?

    func registerTriggers(_ triggers: [Trigger]) {
        unregisterAll()
        let mouseTriggers = triggers.filter {
            if case .mouseButton = $0.input { return $0.isEnabled }
            return false
        }

        for trigger in mouseTriggers {
            if case .mouseButton(let button) = trigger.input {
                registeredTriggers.append((
                    id: trigger.id,
                    button: button,
                    actions: trigger.actions,
                    appBundleID: trigger.appBundleID,
                    suppressClick: trigger.suppressClick
                ))
            }
        }

        guard !registeredTriggers.isEmpty else { return }

        MouseButtonMonitor.activeMonitor = self

        let eventMask: CGEventMask =
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let monitor = MouseButtonMonitor.activeMonitor else {
                return Unmanaged.passRetained(event)
            }

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passRetained(event)
            }

            // Skip events posted by our own ActionExecutor
            if event.getIntegerValueField(.eventSourceUserData) == 0x475454 {
                return Unmanaged.passRetained(event)
            }

            guard type == .otherMouseDown || type == .otherMouseUp else {
                return Unmanaged.passRetained(event)
            }

            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            guard let button = MouseButton.from(cgButton: buttonNumber) else {
                return Unmanaged.passRetained(event)
            }

            let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            let matching = monitor.registeredTriggers.filter { $0.button == button }
            let appSpecific = matching.filter { $0.appBundleID != nil && $0.appBundleID == frontBundleID }
            let global = matching.filter { $0.appBundleID == nil }
            let toFire = appSpecific.isEmpty ? global : appSpecific

            guard !toFire.isEmpty else {
                return Unmanaged.passRetained(event)
            }

            let globalEnabled = UserDefaults.standard.object(forKey: "GTTGlobalEnabled") as? Bool ?? true
            guard globalEnabled else {
                return Unmanaged.passRetained(event)
            }

            // Only fire actions on mouseDown (not on mouseUp)
            if type == .otherMouseDown {
                DispatchQueue.main.async {
                    for trigger in toFire {
                        ActionExecutor.executeActions(trigger.actions)
                        LiveTouchState.shared.flashTrigger(trigger.id)
                        NotificationCenter.default.post(name: .gestureDidFire, object: nil, userInfo: ["name": trigger.button.rawValue])
                    }
                }
            }

            // Suppress the click (both down and up) if any matched trigger has suppressClick enabled
            let shouldSuppress = toFire.contains { $0.suppressClick }
            if shouldSuppress {
                return nil
            }

            return Unmanaged.passRetained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: nil
        )

        if let tap = eventTap {
            runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            if let source = runLoopSource {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        } else {
            NSLog("[MouseButtonMonitor] Failed to create CGEventTap — check Accessibility permissions")
        }
    }

    func unregisterAll() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if MouseButtonMonitor.activeMonitor === self {
            MouseButtonMonitor.activeMonitor = nil
        }
        registeredTriggers.removeAll()
    }

    deinit {
        unregisterAll()
    }
}
