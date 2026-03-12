import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    var onReady: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarIcon()
        requestAccessibilityPermissions()
        requestAutomationPermission()
        ActionExecutor.startTrackingFrontApp()
        // Small delay to let SwiftUI init AppState
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            onReady?()
        }
    }

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "GutchinTouchTool")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open GutchinTouchTool", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func requestAutomationPermission() {
        // Trigger the permission prompt by trying to send an event to System Events
        DispatchQueue.global(qos: .utility).async {
            let script = NSAppleScript(source: """
                tell application "System Events"
                    return name of first process
                end tell
            """)
            var error: NSDictionary?
            script?.executeAndReturnError(&error)
            if let error = error {
                let msg = error[NSAppleScript.errorMessage] as? String ?? ""
                NSLog("[GTT] Automation permission check: %@", msg)
            } else {
                NSLog("[GTT] Automation permission granted for System Events")
            }
        }
    }

    private func requestAccessibilityPermissions() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            // Always prompt — macOS will show the dialog if not yet granted
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)

            // Also open System Settings directly to the Accessibility pane
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }

            NSLog("[GTT] Accessibility NOT granted — opening System Settings")
        } else {
            NSLog("[GTT] Accessibility already granted")
        }
    }
}
