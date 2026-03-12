import XCTest
@testable import GutchinTouchTool

final class TrackpadPipelineTests: XCTestCase {

    override func tearDown() {
        ActionExecutor.onActionExecuted = nil
        super.tearDown()
    }

    /// Simulates a 4-finger tap through TrackpadMonitor and verifies the action fires.
    func testFourFingerTapTriggersAction() {
        let expectation = expectation(description: "Action should be executed")

        // 1. Build a trigger: 4-finger tap → Send ⌘R
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

        // 2. Register trigger with TrackpadMonitor
        let monitor = TrackpadMonitor()
        monitor.registerTriggers([trigger])

        // 3. Hook into ActionExecutor to capture the fired action
        var firedAction: TriggerAction?
        ActionExecutor.onActionExecuted = { executedAction in
            firedAction = executedAction
            expectation.fulfill()
        }

        // 4. Simulate multitouch frames: 4 fingers down, then lifted
        //    - Frame 1: 4 fingers touch down
        let now = Date().timeIntervalSince1970
        monitor.handleMultitouchFrame(touches: nil, numTouches: 4, timestamp: now)

        //    - Small delay then fingers lift (within tap timeout of 0.35s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(touches: nil, numTouches: 0, timestamp: now + 0.1)
        }

        // 5. Wait for the action to fire
        waitForExpectations(timeout: 2.0)

        // 6. Verify the correct action was triggered
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
        monitor.handleMultitouchFrame(touches: nil, numTouches: 3, timestamp: now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            monitor.handleMultitouchFrame(touches: nil, numTouches: 0, timestamp: now + 0.1)
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
        monitor.handleMultitouchFrame(touches: nil, numTouches: 4, timestamp: now)

        // Lift after 0.5s — exceeds the 0.35s tap timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            monitor.handleMultitouchFrame(touches: nil, numTouches: 0, timestamp: now + 0.5)
        }

        waitForExpectations(timeout: 2.0)
        monitor.unregisterAll()
    }
}
