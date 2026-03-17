import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    var onReady: (() -> Void)?
    var appState: AppState?
    private weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBarIcon()
        requestAccessibilityPermissions()
        requestAutomationPermission()
        ActionExecutor.startTrackingFrontApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            onReady?()
            if let window = NSApp.windows.first(where: { $0.isVisible }) {
                window.minSize = NSSize(width: 1300, height: 650)
                mainWindow = window
                window.delegate = self
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    // MARK: - Menu Bar

    private func setupMenuBarIcon() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "hand.point.up.braille", accessibilityDescription: "GutchinTouchTool")
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        let menu = NSMenu()

        // Version header
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "GutchinTouchTool v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(NSMenuItem.separator())

        // Toggle ON/OFF
        let enabled = MainActor.assumeIsolated { appState?.globalEnabled ?? true }
        let toggleItem = NSMenuItem(title: enabled ? "Disable Gestures" : "Enable Gestures", action: #selector(toggleEnabled), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.image = NSImage(systemSymbolName: enabled ? "hand.raised.fill" : "hand.raised.slash.fill", accessibilityDescription: nil)
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Open main window
        let openItem = NSMenuItem(title: "Open Main Window", action: #selector(showMainWindow), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
        menu.addItem(openItem)

        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        // Check for updates
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit GutchinTouchTool", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        // Show the menu
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Clear the menu after it closes so the next click triggers statusItemClicked again
        DispatchQueue.main.async {
            self.statusItem?.menu = nil
        }
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        MainActor.assumeIsolated {
            appState?.toggleGlobalEnabled()
        }
        updateStatusIcon()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Find and invoke the Settings menu item from the app menu
        if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu {
            for item in appMenu.items {
                if item.title.contains("Settings") || item.title.contains("Preferences") {
                    _ = item.target?.perform(item.action, with: item)
                    return
                }
            }
        }
        // Fallback: try the known selector directly
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func checkForUpdates() {
        guard let updateChecker = appState?.updateChecker else { return }
        Task { @MainActor in
            await updateChecker.checkForUpdate()
            if case .available(let version, _) = updateChecker.status {
                let alert = NSAlert()
                alert.messageText = "Update Available"
                alert.informativeText = "Version \(version) is available. Would you like to download and install it?"
                alert.addButton(withTitle: "Update & Restart")
                alert.addButton(withTitle: "Later")
                alert.alertStyle = .informational
                if alert.runModal() == .alertFirstButtonReturn {
                    if case .available(_, let url) = updateChecker.status {
                        await updateChecker.downloadAndInstall(url: url)
                    }
                }
            } else if case .upToDate = updateChecker.status {
                let alert = NSAlert()
                alert.messageText = "You're Up to Date"
                alert.informativeText = "GutchinTouchTool is already on the latest version."
                alert.addButton(withTitle: "OK")
                alert.alertStyle = .informational
                alert.runModal()
            }
        }
    }

    // MARK: - Window management

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    @objc private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Find any suitable window
            for window in NSApp.windows where window.canBecomeMain {
                mainWindow = window
                window.delegate = self
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let enabled = MainActor.assumeIsolated { appState?.globalEnabled ?? true }
        let symbolName = enabled ? "hand.point.up.braille" : "hand.raised.slash"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "GutchinTouchTool")
    }

    // MARK: - Permissions

    private func requestAutomationPermission() {
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
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
            NSLog("[GTT] Accessibility NOT granted — opening System Settings")
        } else {
            NSLog("[GTT] Accessibility already granted")
        }
    }
}
