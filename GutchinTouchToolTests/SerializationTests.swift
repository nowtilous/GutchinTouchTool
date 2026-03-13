import XCTest
@testable import GutchinTouchTool

final class SerializationTests: XCTestCase {

    // MARK: - Trigger Codable

    func testTriggerRoundTrip() throws {
        var trigger = Trigger(name: "Test", input: .trackpadGesture(.fourFingerTap))
        trigger.actions = [TriggerAction(actionType: .volumeUp)]

        let encoder = JSONEncoder()
        let data = try encoder.encode(trigger)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Trigger.self, from: data)

        XCTAssertEqual(decoded.id, trigger.id)
        XCTAssertEqual(decoded.name, "Test")
        XCTAssertEqual(decoded.actions.count, 1)
        XCTAssertEqual(decoded.actions.first?.actionType, .volumeUp)
        XCTAssertTrue(decoded.isEnabled)
    }

    func testTriggerWithKeyboardShortcutRoundTrip() throws {
        let shortcut = KeyboardShortcut(keyCode: 15, modifiers: [.command, .shift])
        var trigger = Trigger(name: "Hotkey", input: .keyboardShortcut(shortcut))
        trigger.actions = [TriggerAction(actionType: .sendKeyStroke, parameters: {
            var p = ActionParameters()
            p.shortcutKeyCode = 49
            p.shortcutModifiers = NSEvent.ModifierFlags.command.rawValue
            return p
        }())]

        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(Trigger.self, from: data)

        if case .keyboardShortcut(let ks) = decoded.input {
            XCTAssertEqual(ks.keyCode, 15)
            XCTAssertTrue(ks.modifiers.contains(.command))
            XCTAssertTrue(ks.modifiers.contains(.shift))
        } else {
            XCTFail("Expected keyboard shortcut input")
        }

        XCTAssertEqual(decoded.actions.first?.parameters.shortcutKeyCode, 49)
    }

    func testTriggerWithMouseButtonRoundTrip() throws {
        let trigger = Trigger(name: "Mouse", input: .mouseButton(.button4))

        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(Trigger.self, from: data)

        if case .mouseButton(let btn) = decoded.input {
            XCTAssertEqual(btn, .button4)
        } else {
            XCTFail("Expected mouse button input")
        }
    }

    // MARK: - ActionParameters Codable

    func testActionParametersRoundTrip() throws {
        var params = ActionParameters()
        params.text = "hello"
        params.applicationPath = "/Applications/Safari.app"
        params.applicationName = "Safari"
        params.scriptContent = "tell app \"Finder\" to activate"
        params.url = "https://example.com"
        params.shortcutKeyCode = 15
        params.shortcutModifiers = 256
        params.delayBeforeMs = 500

        let data = try JSONEncoder().encode(params)
        let decoded = try JSONDecoder().decode(ActionParameters.self, from: data)

        XCTAssertEqual(decoded.text, "hello")
        XCTAssertEqual(decoded.applicationPath, "/Applications/Safari.app")
        XCTAssertEqual(decoded.applicationName, "Safari")
        XCTAssertEqual(decoded.scriptContent, "tell app \"Finder\" to activate")
        XCTAssertEqual(decoded.url, "https://example.com")
        XCTAssertEqual(decoded.shortcutKeyCode, 15)
        XCTAssertEqual(decoded.shortcutModifiers, 256)
        XCTAssertEqual(decoded.delayBeforeMs, 500)
    }

    // MARK: - Preset Codable

    func testPresetRoundTrip() throws {
        var preset = Preset(name: "My Preset")
        var trigger = Trigger(name: "T1", input: .trackpadGesture(.twoFingerSwipeLeft))
        trigger.actions = [TriggerAction(actionType: .snapWindowLeft)]
        preset.addTrigger(trigger)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(preset)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Preset.self, from: data)

        XCTAssertEqual(decoded.name, "My Preset")
        XCTAssertEqual(decoded.triggers.count, 1)
        XCTAssertEqual(decoded.triggers.first?.actions.first?.actionType, .snapWindowLeft)
    }

    // MARK: - Preset export/import

    func testPresetExportImportRoundTrip() throws {
        var preset = Preset(name: "Export Test")
        var t1 = Trigger(name: "Swipe", input: .trackpadGesture(.twoFingerSwipeRight))
        t1.actions = [TriggerAction(actionType: .snapWindowRight)]
        preset.addTrigger(t1)

        var t2 = Trigger(name: "Tap", input: .trackpadGesture(.threeFingerTap))
        t2.actions = [
            TriggerAction(actionType: .volumeUp),
            TriggerAction(actionType: .playPause)
        ]
        preset.addTrigger(t2)

        let manager = PresetManager()
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_preset_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        manager.exportPreset(preset, to: tmpURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpURL.path))

        let imported = manager.importPreset(from: tmpURL)
        XCTAssertNotNil(imported)
        XCTAssertEqual(imported?.name, "Export Test")
        XCTAssertEqual(imported?.triggers.count, 2)

        let swipeTrigger = imported?.triggers.first { $0.name == "Swipe" }
        XCTAssertNotNil(swipeTrigger)
        XCTAssertEqual(swipeTrigger?.actions.first?.actionType, .snapWindowRight)

        let tapTrigger = imported?.triggers.first { $0.name == "Tap" }
        XCTAssertNotNil(tapTrigger)
        XCTAssertEqual(tapTrigger?.actions.count, 2)
    }

    func testImportFromInvalidFileReturnsNil() {
        let manager = PresetManager()
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("bad_\(UUID().uuidString).json")
        try? "not json".data(using: .utf8)?.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let result = manager.importPreset(from: tmpURL)
        XCTAssertNil(result)
    }

    func testImportFromNonexistentFileReturnsNil() {
        let manager = PresetManager()
        let result = manager.importPreset(from: URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).json"))
        XCTAssertNil(result)
    }

    // MARK: - All gesture types are Codable

    func testAllTrackpadGesturesCodable() throws {
        for gesture in TrackpadGesture.allCases {
            let input = TriggerInput.trackpadGesture(gesture)
            let trigger = Trigger(name: gesture.rawValue, input: input)
            let data = try JSONEncoder().encode(trigger)
            let decoded = try JSONDecoder().decode(Trigger.self, from: data)
            if case .trackpadGesture(let g) = decoded.input {
                XCTAssertEqual(g, gesture, "Round-trip failed for \(gesture)")
            } else {
                XCTFail("Decoded input is not trackpadGesture for \(gesture)")
            }
        }
    }

    func testAllActionTypesCodable() throws {
        for actionType in ActionType.allCases {
            let action = TriggerAction(actionType: actionType)
            let data = try JSONEncoder().encode(action)
            let decoded = try JSONDecoder().decode(TriggerAction.self, from: data)
            XCTAssertEqual(decoded.actionType, actionType, "Round-trip failed for \(actionType)")
        }
    }
}
