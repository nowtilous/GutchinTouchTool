import XCTest
@testable import GutchinTouchTool

final class ModelTests: XCTestCase {

    // MARK: - Trigger model

    func testTriggerDefaultValues() {
        let trigger = Trigger(name: "Test", input: .trackpadGesture(.twoFingerTap))
        XCTAssertTrue(trigger.isEnabled)
        XCTAssertNil(trigger.appBundleID)
        XCTAssertTrue(trigger.actions.isEmpty)
        XCTAssertEqual(trigger.order, 0)
    }

    func testTriggerDisplayNameFallsBackToInput() {
        let trigger = Trigger(name: "", input: .trackpadGesture(.threeFingerSwipeUp))
        XCTAssertEqual(trigger.displayName, "3 Finger Swipe Up")
    }

    func testTriggerDisplayNameUsesCustomName() {
        let trigger = Trigger(name: "My Gesture", input: .trackpadGesture(.threeFingerSwipeUp))
        XCTAssertEqual(trigger.displayName, "My Gesture")
    }

    func testTriggerInputCategory() {
        XCTAssertEqual(TriggerInput.trackpadGesture(.twoFingerTap).category, .trackpad)
        XCTAssertEqual(TriggerInput.keyboardShortcut(KeyboardShortcut(keyCode: 0, modifiers: .command)).category, .keyboard)
        XCTAssertEqual(TriggerInput.mouseButton(.button3).category, .normalMouse)
        XCTAssertEqual(TriggerInput.drawingPattern("circle").category, .drawings)
        XCTAssertEqual(TriggerInput.namedTrigger("custom").category, .otherTriggers)
    }

    // MARK: - Action model

    func testActionParametersDefaultsNil() {
        let params = ActionParameters()
        XCTAssertNil(params.text)
        XCTAssertNil(params.applicationPath)
        XCTAssertNil(params.scriptContent)
        XCTAssertNil(params.url)
        XCTAssertNil(params.shortcutKeyCode)
        XCTAssertNil(params.shortcutModifiers)
        XCTAssertNil(params.delayBeforeMs)
    }

    func testTriggerActionDefaultEnabled() {
        let action = TriggerAction(actionType: .volumeUp)
        XCTAssertTrue(action.isEnabled)
    }

    func testActionTypeCategories() {
        XCTAssertEqual(ActionType.maximizeWindow.category, .windowManagement)
        XCTAssertEqual(ActionType.sendKeyStroke.category, .keyboardActions)
        XCTAssertEqual(ActionType.launchApplication.category, .applicationControl)
        XCTAssertEqual(ActionType.lockScreen.category, .systemActions)
        XCTAssertEqual(ActionType.runShellScript.category, .scriptExecution)
        XCTAssertEqual(ActionType.playPause.category, .mediaControls)
    }

    func testActionsForCategory() {
        let windowActions = ActionType.actionsForCategory(.windowManagement)
        XCTAssertTrue(windowActions.contains(.maximizeWindow))
        XCTAssertTrue(windowActions.contains(.snapWindowLeft))
        XCTAssertFalse(windowActions.contains(.sendKeyStroke))

        let mediaActions = ActionType.actionsForCategory(.mediaControls)
        XCTAssertTrue(mediaActions.contains(.playPause))
        XCTAssertTrue(mediaActions.contains(.nextTrack))
        XCTAssertTrue(mediaActions.contains(.previousTrack))
        XCTAssertEqual(mediaActions.count, 3)
    }

    // MARK: - TrackpadGesture completeness

    func testAllTrackpadGesturesHaveUniqueRawValues() {
        let rawValues = TrackpadGesture.allCases.map { $0.rawValue }
        XCTAssertEqual(rawValues.count, Set(rawValues).count, "Duplicate raw values in TrackpadGesture")
    }

    func testAllActionTypesHaveUniqueRawValues() {
        let rawValues = ActionType.allCases.map { $0.rawValue }
        XCTAssertEqual(rawValues.count, Set(rawValues).count, "Duplicate raw values in ActionType")
    }

    func testAllActionTypesHaveIcons() {
        for actionType in ActionType.allCases {
            XCTAssertFalse(actionType.iconName.isEmpty, "\(actionType) has no icon")
        }
    }

    // MARK: - Preset model

    func testPresetDefaultValues() {
        let preset = Preset(name: "Test Preset")
        XCTAssertEqual(preset.name, "Test Preset")
        XCTAssertTrue(preset.isEnabled)
        XCTAssertFalse(preset.isMaster)
        XCTAssertTrue(preset.triggers.isEmpty)
    }

    func testPresetAddTrigger() {
        var preset = Preset(name: "P")
        let trigger = Trigger(name: "T", input: .trackpadGesture(.twoFingerTap))
        preset.addTrigger(trigger)
        XCTAssertEqual(preset.triggers.count, 1)
        XCTAssertEqual(preset.triggers.first?.name, "T")
    }

    func testPresetRemoveTrigger() {
        var preset = Preset(name: "P")
        let trigger = Trigger(name: "T", input: .trackpadGesture(.twoFingerTap))
        preset.addTrigger(trigger)
        XCTAssertEqual(preset.triggers.count, 1)
        preset.removeTrigger(id: trigger.id)
        XCTAssertTrue(preset.triggers.isEmpty)
    }

    func testPresetUpdateTrigger() {
        var preset = Preset(name: "P")
        var trigger = Trigger(name: "Original", input: .trackpadGesture(.twoFingerTap))
        preset.addTrigger(trigger)

        trigger.name = "Updated"
        preset.updateTrigger(trigger)

        XCTAssertEqual(preset.triggers.first?.name, "Updated")
    }

    func testPresetFilterByAppAndCategory() {
        var preset = Preset(name: "P")

        var t1 = Trigger(name: "Global Tap", input: .trackpadGesture(.twoFingerTap))
        t1 = Trigger(name: "Global Tap", input: .trackpadGesture(.twoFingerTap), appBundleID: nil)
        preset.addTrigger(t1)

        let t2 = Trigger(name: "App Tap", input: .trackpadGesture(.threeFingerTap), appBundleID: "com.test.app")
        preset.addTrigger(t2)

        let t3 = Trigger(name: "App Key", input: .keyboardShortcut(KeyboardShortcut(keyCode: 0, modifiers: .command)), appBundleID: "com.test.app")
        preset.addTrigger(t3)

        let appTarget = AppTarget(id: UUID(), bundleID: "com.test.app", name: "Test", iconPath: nil)
        let appTrackpad = preset.triggers(for: appTarget, category: .trackpad)
        XCTAssertEqual(appTrackpad.count, 1)
        XCTAssertEqual(appTrackpad.first?.name, "App Tap")

        let appKeyboard = preset.triggers(for: appTarget, category: .keyboard)
        XCTAssertEqual(appKeyboard.count, 1)
        XCTAssertEqual(appKeyboard.first?.name, "App Key")
    }

    // MARK: - KeyboardShortcut

    func testKeyboardShortcutDisplayString() {
        let shortcut = KeyboardShortcut(keyCode: 15, modifiers: [.command, .shift])
        let display = shortcut.displayString
        XCTAssertTrue(display.contains("⌘"))
        XCTAssertTrue(display.contains("⇧"))
        XCTAssertTrue(display.contains("R"))
    }

    func testKeyboardShortcutDisplayStringAllModifiers() {
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.control, .option, .shift, .command])
        let display = shortcut.displayString
        XCTAssertTrue(display.contains("⌃"))
        XCTAssertTrue(display.contains("⌥"))
        XCTAssertTrue(display.contains("⇧"))
        XCTAssertTrue(display.contains("⌘"))
        XCTAssertTrue(display.contains("A"))
    }
}
