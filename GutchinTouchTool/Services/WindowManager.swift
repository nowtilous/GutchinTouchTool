import Foundation
import AppKit

enum SnapPosition {
    case left, right, topLeft, topRight, bottomLeft, bottomRight
}

class WindowManager {
    static let shared = WindowManager()
    private var previousFrames: [CGWindowID: CGRect] = [:]

    func maximizeWindow() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        setFrontWindowFrame(frame)
    }

    func minimizeWindow() {
        if let app = NSWorkspace.shared.frontmostApplication {
            let source = CGEventSource(stateID: .hidSystemState)
            let mDown = CGEvent(keyboardEventSource: source, virtualKey: 46, keyDown: true)
            mDown?.flags = .maskCommand
            let mUp = CGEvent(keyboardEventSource: source, virtualKey: 46, keyDown: false)
            mUp?.flags = .maskCommand
            mDown?.post(tap: .cghidEventTap)
            mUp?.post(tap: .cghidEventTap)
            _ = app // silence unused warning
        }
    }

    func snapWindow(_ position: SnapPosition) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let halfW = visible.width / 2
        let halfH = visible.height / 2

        let frame: CGRect
        switch position {
        case .left:
            frame = CGRect(x: visible.minX, y: visible.minY, width: halfW, height: visible.height)
        case .right:
            frame = CGRect(x: visible.midX, y: visible.minY, width: halfW, height: visible.height)
        case .topLeft:
            frame = CGRect(x: visible.minX, y: visible.midY, width: halfW, height: halfH)
        case .topRight:
            frame = CGRect(x: visible.midX, y: visible.midY, width: halfW, height: halfH)
        case .bottomLeft:
            frame = CGRect(x: visible.minX, y: visible.minY, width: halfW, height: halfH)
        case .bottomRight:
            frame = CGRect(x: visible.midX, y: visible.minY, width: halfW, height: halfH)
        }
        setFrontWindowFrame(frame)
    }

    func centerWindow() {
        guard let screen = NSScreen.main else { return }
        guard let windowInfo = getFrontWindowInfo() else { return }
        let visible = screen.visibleFrame
        let windowFrame = windowInfo.frame
        let x = visible.minX + (visible.width - windowFrame.width) / 2
        let y = visible.minY + (visible.height - windowFrame.height) / 2
        let frame = CGRect(x: x, y: y, width: windowFrame.width, height: windowFrame.height)
        setFrontWindowFrame(frame)
    }

    func moveToNextMonitor() {
        guard NSScreen.screens.count > 1 else { return }
        guard let windowInfo = getFrontWindowInfo() else { return }

        let currentCenter = CGPoint(
            x: windowInfo.frame.midX,
            y: windowInfo.frame.midY
        )

        var currentScreenIndex = 0
        for (index, screen) in NSScreen.screens.enumerated() {
            if screen.frame.contains(currentCenter) {
                currentScreenIndex = index
                break
            }
        }

        let nextIndex = (currentScreenIndex + 1) % NSScreen.screens.count
        let nextScreen = NSScreen.screens[nextIndex]
        let visible = nextScreen.visibleFrame

        let newFrame = CGRect(
            x: visible.minX + (visible.width - windowInfo.frame.width) / 2,
            y: visible.minY + (visible.height - windowInfo.frame.height) / 2,
            width: windowInfo.frame.width,
            height: windowInfo.frame.height
        )
        setFrontWindowFrame(newFrame)
    }

    func restoreWindow() {
        guard let windowInfo = getFrontWindowInfo(),
              let previous = previousFrames[windowInfo.id] else { return }
        setFrontWindowFrame(previous)
        previousFrames.removeValue(forKey: windowInfo.id)
    }

    // MARK: - Private

    private struct WindowInfo {
        let id: CGWindowID
        let frame: CGRect
        let pid: pid_t
    }

    private func getFrontWindowInfo() -> WindowInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []

        for info in windowList {
            guard let windowPID = info[kCGWindowOwnerPID] as? pid_t,
                  windowPID == pid,
                  let bounds = info[kCGWindowBounds] as? [String: CGFloat],
                  let windowID = info[kCGWindowNumber] as? CGWindowID else { continue }

            let frame = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )
            return WindowInfo(id: windowID, frame: frame, pid: pid)
        }
        return nil
    }

    private func setFrontWindowFrame(_ frame: CGRect) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier

        let appRef = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appRef, kAXFocusedWindowAttribute as CFString, &windowRef)

        guard let window = windowRef else { return }

        // Save current frame for restore
        if let info = getFrontWindowInfo() {
            previousFrames[info.id] = info.frame
        }

        var position = CGPoint(x: frame.origin.x, y: frame.origin.y)
        var size = CGSize(width: frame.width, height: frame.height)

        let posValue = AXValueCreate(.cgPoint, &position)!
        let sizeValue = AXValueCreate(.cgSize, &size)!

        AXUIElementSetAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, posValue)
        AXUIElementSetAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, sizeValue)
    }
}
