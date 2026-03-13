import XCTest
@testable import GutchinTouchTool

final class TrackpadPipelineTests: XCTestCase {

    override func tearDown() {
        ActionExecutor.onActionExecuted = nil
        super.tearDown()
    }

    // MARK: - Tap gesture tests

    /// Simulates a 4-finger tap through TrackpadMonitor and verifies the action fires.
    func testFourFingerTapTriggersAction() {
        let expectation = expectation(description: "Action should be executed")

        var trigger = Trigger(name: "Test 4-Finger Tap", input: .trackpadGesture(.fourFingerTap))
        let action = TriggerAction(
            actionType: .sendKeyStroke,
            parameters: {
                var p = ActionParameters()
                p.shortcutKeyCode = 15  // R key
                p.shortcutModifiers = NSEvent.ModifierFlags.command.rawValue
                return p
            }()
        )
        trigger.actions = [action]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { executedAction in
            firedAction = executedAction
            expectation.fulfill()
        }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 4, timestamp: now)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 2.0)

        XCTAssertNotNil(firedAction, "Action should have been triggered by 4-finger tap")
        XCTAssertEqual(firedAction?.actionType, .sendKeyStroke)
        XCTAssertEqual(firedAction?.parameters.shortcutKeyCode, 15)
        XCTAssertEqual(firedAction?.parameters.shortcutModifiers, NSEvent.ModifierFlags.command.rawValue)

        monitor.unregisterAll()
    }

    /// Verifies that a 3-finger tap does NOT trigger a 4-finger tap action.
    func testThreeFingerTapDoesNotTriggerFourFingerAction() {
        let expectation = expectation(description: "Action should NOT fire")
        expectation.isInverted = true

        var trigger = Trigger(name: "4-Finger Only", input: .trackpadGesture(.fourFingerTap))
        trigger.actions = [TriggerAction(actionType: .sendKeyStroke)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        ActionExecutor.onActionExecuted = { _ in
            expectation.fulfill()
        }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 3, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 1.0)
        monitor.unregisterAll()
    }

    /// Verifies that holding fingers too long counts as a hold, not a tap.
    func testLongHoldDoesNotTriggerTap() {
        let expectation = expectation(description: "Action should NOT fire for long hold")
        expectation.isInverted = true

        var trigger = Trigger(name: "Tap", input: .trackpadGesture(.fourFingerTap))
        trigger.actions = [TriggerAction(actionType: .sendKeyStroke)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        ActionExecutor.onActionExecuted = { _ in
            expectation.fulfill()
        }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 4, timestamp: now)

        // Lift after 0.5s — exceeds the 0.35s tap timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.5)
        }

        waitForExpectations(timeout: 2.0)
        monitor.unregisterAll()
    }

    func testThreeFingerTapTriggersAction() {
        let expectation = expectation(description: "3-finger tap fires")

        var trigger = Trigger(name: "3-Finger Tap", input: .trackpadGesture(.threeFingerTap))
        trigger.actions = [TriggerAction(actionType: .volumeUp)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { a in
            firedAction = a
            expectation.fulfill()
        }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 3, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(firedAction?.actionType, .volumeUp)
        monitor.unregisterAll()
    }

    func testFiveFingerTapTriggersAction() {
        let expectation = expectation(description: "5-finger tap fires")

        var trigger = Trigger(name: "5-Finger Tap", input: .trackpadGesture(.fiveFingerTap))
        trigger.actions = [TriggerAction(actionType: .lockScreen)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { a in
            firedAction = a
            expectation.fulfill()
        }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 5, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(firedAction?.actionType, .lockScreen)
        monitor.unregisterAll()
    }

    /// 2-finger tap does NOT fire 3-finger tap
    func testTwoFingerTapDoesNotTriggerThreeFingerAction() {
        let expectation = expectation(description: "Should NOT fire")
        expectation.isInverted = true

        var trigger = Trigger(name: "3-Finger Only", input: .trackpadGesture(.threeFingerTap))
        trigger.actions = [TriggerAction(actionType: .sendKeyStroke)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        ActionExecutor.onActionExecuted = { _ in expectation.fulfill() }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 2, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 1.0)
        monitor.unregisterAll()
    }

    // MARK: - Peak finger tracking

    /// Fingers ramp up 1→2→3→4 then lift — should fire 4-finger tap (peak)
    func testPeakFingerCountTracked() {
        let expectation = expectation(description: "4-finger tap via ramp-up")

        var trigger = Trigger(name: "4F", input: .trackpadGesture(.fourFingerTap))
        trigger.actions = [TriggerAction(actionType: .playPause)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { a in
            firedAction = a
            expectation.fulfill()
        }

        let now = Date().timeIntervalSince1970
        // Fingers land progressively
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 1, timestamp: now)
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 2, timestamp: now + 0.02)
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 3, timestamp: now + 0.04)
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 4, timestamp: now + 0.06)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.15)
        }

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(firedAction?.actionType, .playPause)
        monitor.unregisterAll()
    }

    // MARK: - Multiple triggers / routing

    /// Two different gestures registered, only the matching one fires
    func testMultipleTriggerRoutesCorrectly() {
        let exp3 = expectation(description: "3-finger should fire")
        let exp4 = expectation(description: "4-finger should NOT fire")
        exp4.isInverted = true

        var trigger3 = Trigger(name: "3F", input: .trackpadGesture(.threeFingerTap))
        trigger3.actions = [TriggerAction(actionType: .volumeUp)]

        var trigger4 = Trigger(name: "4F", input: .trackpadGesture(.fourFingerTap))
        trigger4.actions = [TriggerAction(actionType: .volumeDown)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger3, trigger4])

        ActionExecutor.onActionExecuted = { a in
            if a.actionType == .volumeUp { exp3.fulfill() }
            if a.actionType == .volumeDown { exp4.fulfill() }
        }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 3, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 2.0)
        monitor.unregisterAll()
    }

    // MARK: - Disabled trigger

    func testDisabledTriggerDoesNotFire() {
        let expectation = expectation(description: "Should NOT fire")
        expectation.isInverted = true

        var trigger = Trigger(name: "Disabled", input: .trackpadGesture(.fourFingerTap))
        trigger.actions = [TriggerAction(actionType: .sendKeyStroke)]
        trigger.isEnabled = false

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        ActionExecutor.onActionExecuted = { _ in expectation.fulfill() }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 4, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 1.0)
        monitor.unregisterAll()
    }

    // MARK: - Unregister clears state

    func testUnregisterClearsAllTriggers() {
        let expectation = expectation(description: "Should NOT fire after unregister")
        expectation.isInverted = true

        var trigger = Trigger(name: "T", input: .trackpadGesture(.fourFingerTap))
        trigger.actions = [TriggerAction(actionType: .sendKeyStroke)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])
        monitor.unregisterAll()

        ActionExecutor.onActionExecuted = { _ in expectation.fulfill() }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 4, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 1.0)
    }

    // MARK: - App-specific vs global trigger priority

    /// When an app-specific trigger exists for a different app, the global trigger fires instead
    func testGlobalTriggerFiresWhenNoAppMatch() {
        let globalExp = self.expectation(description: "Global fires")
        let appExp = self.expectation(description: "App-specific should NOT fire")
        appExp.isInverted = true

        var globalTrigger = Trigger(name: "Global", input: .trackpadGesture(.threeFingerTap))
        globalTrigger.actions = [TriggerAction(actionType: .volumeUp)]

        // Use a fake bundle ID that won't match the frontmost app
        var appTrigger = Trigger(name: "App", input: .trackpadGesture(.threeFingerTap), appBundleID: "com.fake.nonexistent.app")
        appTrigger.actions = [TriggerAction(actionType: .volumeDown)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([globalTrigger, appTrigger])

        ActionExecutor.onActionExecuted = { a in
            if a.actionType == .volumeUp { globalExp.fulfill() }
            if a.actionType == .volumeDown { appExp.fulfill() }
        }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 3, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 2.0)
        monitor.unregisterAll()
    }

    // MARK: - Multiple actions on single trigger

    func testMultipleActionsAllFire() {
        let exp1 = expectation(description: "Action 1 fires")
        let exp2 = expectation(description: "Action 2 fires")

        var trigger = Trigger(name: "Multi", input: .trackpadGesture(.fourFingerTap))
        trigger.actions = [
            TriggerAction(actionType: .volumeUp),
            TriggerAction(actionType: .playPause)
        ]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        ActionExecutor.onActionExecuted = { a in
            if a.actionType == .volumeUp { exp1.fulfill() }
            if a.actionType == .playPause { exp2.fulfill() }
        }

        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 4, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(rawTouches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        waitForExpectations(timeout: 2.0)
        monitor.unregisterAll()
    }

    // MARK: - Two-finger press-drag tests

    func testTwoFingerPressDragLeftTriggersAction() {
        let expectation = expectation(description: "Press drag left fires")

        var trigger = Trigger(name: "Drag Left", input: .trackpadGesture(.twoFingerPressDragLeft))
        trigger.actions = [TriggerAction(actionType: .snapWindowLeft)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { a in
            firedAction = a
            expectation.fulfill()
        }

        monitor.fireGestureForTest(.twoFingerPressDragLeft)

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(firedAction?.actionType, .snapWindowLeft)
        monitor.unregisterAll()
    }

    func testTwoFingerPressDragRightTriggersAction() {
        let expectation = expectation(description: "Press drag right fires")

        var trigger = Trigger(name: "Drag Right", input: .trackpadGesture(.twoFingerPressDragRight))
        trigger.actions = [TriggerAction(actionType: .snapWindowRight)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { a in
            firedAction = a
            expectation.fulfill()
        }

        monitor.fireGestureForTest(.twoFingerPressDragRight)

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(firedAction?.actionType, .snapWindowRight)
        monitor.unregisterAll()
    }

    func testPressDragLeftDoesNotFireDragRight() {
        let expectation = expectation(description: "Should NOT fire")
        expectation.isInverted = true

        var trigger = Trigger(name: "Right Only", input: .trackpadGesture(.twoFingerPressDragRight))
        trigger.actions = [TriggerAction(actionType: .sendKeyStroke)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        ActionExecutor.onActionExecuted = { _ in expectation.fulfill() }

        monitor.fireGestureForTest(.twoFingerPressDragLeft)

        waitForExpectations(timeout: 1.0)
        monitor.unregisterAll()
    }

    func testPressDragGesturesCodable() throws {
        for gesture in [TrackpadGesture.twoFingerPressDragLeft, .twoFingerPressDragRight] {
            let trigger = Trigger(name: gesture.rawValue, input: .trackpadGesture(gesture))
            let data = try JSONEncoder().encode(trigger)
            let decoded = try JSONDecoder().decode(Trigger.self, from: data)
            if case .trackpadGesture(let g) = decoded.input {
                XCTAssertEqual(g, gesture)
            } else {
                XCTFail("Expected trackpadGesture for \(gesture)")
            }
        }
    }

    // MARK: - Edge slider tests

    func testLeftEdgeSlideUpTriggersAction() {
        let expectation = expectation(description: "Left edge slide up fires")

        var trigger = Trigger(name: "L Slide Up", input: .trackpadGesture(.leftEdgeSlideUp))
        trigger.actions = [TriggerAction(actionType: .brightnessUp)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { a in
            firedAction = a
            expectation.fulfill()
        }

        monitor.fireGestureForTest(.leftEdgeSlideUp)

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(firedAction?.actionType, .brightnessUp)
        monitor.unregisterAll()
    }

    func testRightEdgeSlideDownTriggersAction() {
        let expectation = expectation(description: "Right edge slide down fires")

        var trigger = Trigger(name: "R Slide Down", input: .trackpadGesture(.rightEdgeSlideDown))
        trigger.actions = [TriggerAction(actionType: .brightnessDown)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { a in
            firedAction = a
            expectation.fulfill()
        }

        monitor.fireGestureForTest(.rightEdgeSlideDown)

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(firedAction?.actionType, .brightnessDown)
        monitor.unregisterAll()
    }

    func testEdgeSlideUpDoesNotFireSlideDown() {
        let expectation = expectation(description: "Should NOT fire")
        expectation.isInverted = true

        var trigger = Trigger(name: "Down Only", input: .trackpadGesture(.rightEdgeSlideDown))
        trigger.actions = [TriggerAction(actionType: .sendKeyStroke)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        ActionExecutor.onActionExecuted = { _ in expectation.fulfill() }

        monitor.fireGestureForTest(.rightEdgeSlideUp)

        waitForExpectations(timeout: 1.0)
        monitor.unregisterAll()
    }

    func testEdgeSliderGesturesCodable() throws {
        let gestures: [TrackpadGesture] = [.leftEdgeSlideUp, .leftEdgeSlideDown, .rightEdgeSlideUp, .rightEdgeSlideDown]
        for gesture in gestures {
            let trigger = Trigger(name: gesture.rawValue, input: .trackpadGesture(gesture))
            let data = try JSONEncoder().encode(trigger)
            let decoded = try JSONDecoder().decode(Trigger.self, from: data)
            if case .trackpadGesture(let g) = decoded.input {
                XCTAssertEqual(g, gesture)
            } else {
                XCTFail("Expected trackpadGesture for \(gesture)")
            }
        }
    }

    // MARK: - Triangle drawing tests

    func testDrawTriangleTriggersAction() {
        let expectation = expectation(description: "Triangle fires")

        var trigger = Trigger(name: "Triangle", input: .trackpadGesture(.drawTriangle))
        trigger.actions = [TriggerAction(actionType: .lockScreen)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { a in
            firedAction = a
            expectation.fulfill()
        }

        monitor.fireGestureForTest(.drawTriangle)

        waitForExpectations(timeout: 2.0)
        XCTAssertEqual(firedAction?.actionType, .lockScreen)
        monitor.unregisterAll()
    }

    func testDrawTriangleCodable() throws {
        let trigger = Trigger(name: "Tri", input: .trackpadGesture(.drawTriangle))
        let data = try JSONEncoder().encode(trigger)
        let decoded = try JSONDecoder().decode(Trigger.self, from: data)
        if case .trackpadGesture(let g) = decoded.input {
            XCTAssertEqual(g, .drawTriangle)
        } else {
            XCTFail("Expected trackpadGesture drawTriangle")
        }
    }

    // MARK: - Global toggle tests

    func testGlobalToggleOffSuppressesActions() {
        let expectation = expectation(description: "Should NOT fire when disabled")
        expectation.isInverted = true

        var trigger = Trigger(name: "Tap", input: .trackpadGesture(.fourFingerTap))
        trigger.actions = [TriggerAction(actionType: .volumeUp)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        // Disable global toggle
        UserDefaults.standard.set(false, forKey: "GTTGlobalEnabled")

        ActionExecutor.onActionExecuted = { _ in expectation.fulfill() }

        monitor.fireGestureForTest(.fourFingerTap)

        waitForExpectations(timeout: 1.0)

        // Restore
        UserDefaults.standard.removeObject(forKey: "GTTGlobalEnabled")
        monitor.unregisterAll()
    }

    func testGlobalToggleOnAllowsActions() {
        let expectation = expectation(description: "Should fire when enabled")

        var trigger = Trigger(name: "Tap", input: .trackpadGesture(.fourFingerTap))
        trigger.actions = [TriggerAction(actionType: .volumeUp)]

        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        UserDefaults.standard.set(true, forKey: "GTTGlobalEnabled")

        ActionExecutor.onActionExecuted = { _ in expectation.fulfill() }

        monitor.fireGestureForTest(.fourFingerTap)

        waitForExpectations(timeout: 2.0)

        UserDefaults.standard.removeObject(forKey: "GTTGlobalEnabled")
        monitor.unregisterAll()
    }
}
