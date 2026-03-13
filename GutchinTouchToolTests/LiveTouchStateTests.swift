import XCTest
@testable import GutchinTouchTool

@MainActor
final class LiveTouchStateTests: XCTestCase {

    // MARK: - Touch updates

    func testUpdateSetsPoints() async {
        let state = LiveTouchState()
        let points = [
            TouchPoint(id: 1, x: 0.5, y: 0.5, size: 5.0),
            TouchPoint(id: 2, x: 0.3, y: 0.7, size: 4.0)
        ]

        state.update(points)
        // Wait for the Task to execute
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(state.touches.count, 2)
        XCTAssertEqual(state.touches[0].id, 1)
        XCTAssertEqual(state.touches[1].id, 2)
    }

    func testUpdateClearsPressOnEmptyPoints() async {
        let state = LiveTouchState()

        // Simulate pressed state
        state.isPressed = true
        XCTAssertTrue(state.isPressed)

        // Update with empty (all fingers lifted)
        state.update([])
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(state.isPressed)
    }

    func testUpdateDoesNotClearPressWithActiveFingers() async {
        let state = LiveTouchState()
        state.isPressed = true

        state.update([TouchPoint(id: 1, x: 0.5, y: 0.5, size: 5.0)])
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertTrue(state.isPressed)
    }

    // MARK: - Trail tracking

    func testTrailsBuiltFromUpdates() async {
        let state = LiveTouchState()

        state.update([TouchPoint(id: 1, x: 0.2, y: 0.3, size: 5.0)])
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.update([TouchPoint(id: 1, x: 0.25, y: 0.35, size: 5.0)])
        try? await Task.sleep(nanoseconds: 50_000_000)
        state.update([TouchPoint(id: 1, x: 0.3, y: 0.4, size: 5.0)])
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(state.trails[1])
        XCTAssertEqual(state.trails[1]?.count, 3)
    }

    func testTrailsSeparatePerFinger() async {
        let state = LiveTouchState()

        state.update([
            TouchPoint(id: 1, x: 0.2, y: 0.3, size: 5.0),
            TouchPoint(id: 2, x: 0.8, y: 0.7, size: 5.0)
        ])
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(state.trails[1])
        XCTAssertNotNil(state.trails[2])
        XCTAssertEqual(state.trails[1]?.count, 1)
        XCTAssertEqual(state.trails[2]?.count, 1)
    }

    func testStaleTrailsRemovedAfterFingerLifts() async {
        let state = LiveTouchState()

        state.update([TouchPoint(id: 1, x: 0.5, y: 0.5, size: 5.0)])
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNotNil(state.trails[1])

        // Finger lifts — trail should still exist briefly
        state.update([])
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Trail gets cleaned up after max age (0.6s), wait for it
        try? await Task.sleep(nanoseconds: 700_000_000)

        // Force a cleanup tick by sending another empty update
        state.update([])
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertNil(state.trails[1], "Trail should be removed after max age")
    }

    // MARK: - Press state

    func testSetPressed() async {
        let state = LiveTouchState()

        state.setPressed(true)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(state.isPressed)

        state.setPressed(false)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(state.isPressed)
    }

    // MARK: - Gesture flash

    func testFlashTriggerSetsAndClearsID() async {
        let state = LiveTouchState()
        let testID = UUID()

        state.flashTrigger(testID)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.lastFiredTriggerID, testID)

        // Wait for flash to clear (600ms + buffer)
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertNil(state.lastFiredTriggerID)
    }

    func testFlashTriggerReplacedByNewerFlash() async {
        let state = LiveTouchState()
        let id1 = UUID()
        let id2 = UUID()

        state.flashTrigger(id1)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.lastFiredTriggerID, id1)

        state.flashTrigger(id2)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.lastFiredTriggerID, id2)
    }

    // MARK: - TouchPoint identity

    func testTouchPointIdentifiable() {
        let p1 = TouchPoint(id: 1, x: 0.5, y: 0.5, size: 5.0)
        let p2 = TouchPoint(id: 2, x: 0.3, y: 0.7, size: 4.0)
        XCTAssertNotEqual(p1.id, p2.id)
    }
}
