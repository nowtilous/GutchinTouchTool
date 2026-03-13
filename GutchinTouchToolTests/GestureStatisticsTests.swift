import XCTest
@testable import GutchinTouchTool

@MainActor
final class GestureStatisticsTests: XCTestCase {

    private func makeStats(_ events: [GestureEvent] = [], total: Int = 0, fired: Int = 0) -> GestureStatistics {
        GestureStatistics(testEvents: events, totalGestures: total, totalFired: fired)
    }

    // MARK: - Recording

    func testRecordDetectionIncrementsTotalAndAddsEvent() {
        let stats = makeStats()
        stats.recordDetection("4 Finger Tap")

        XCTAssertEqual(stats.totalGestures, 1)
        XCTAssertEqual(stats.events.count, 1)
        XCTAssertEqual(stats.events.first?.gesture, "4 Finger Tap")
        XCTAssertFalse(stats.events.first!.fired)
    }

    func testRecordFireIncrementsFiredAndAddsEvent() {
        let stats = makeStats()
        stats.recordFire("3 Finger Tap")

        XCTAssertEqual(stats.totalFired, 1)
        XCTAssertEqual(stats.events.count, 1)
        XCTAssertTrue(stats.events.first!.fired)
    }

    func testMultipleDetectionsAccumulate() {
        let stats = makeStats()
        stats.recordDetection("4 Finger Tap")
        stats.recordDetection("4 Finger Tap")
        stats.recordDetection("3 Finger Tap")

        XCTAssertEqual(stats.totalGestures, 3)
        XCTAssertEqual(stats.events.count, 3)
    }

    // MARK: - Unmatched count

    func testUnmatchedCount() {
        let stats = makeStats(total: 10, fired: 7)
        XCTAssertEqual(stats.unmatchedCount, 3)
    }

    func testUnmatchedCountAfterRecording() {
        let stats = makeStats()
        stats.recordDetection("A")
        stats.recordDetection("B")
        stats.recordFire("A")

        XCTAssertEqual(stats.unmatchedCount, 1)
    }

    // MARK: - Reset

    func testResetClearsEverything() {
        let stats = makeStats()
        stats.recordDetection("X")
        stats.recordFire("X")
        stats.reset()

        XCTAssertEqual(stats.totalGestures, 0)
        XCTAssertEqual(stats.totalFired, 0)
        XCTAssertTrue(stats.events.isEmpty)
    }

    // MARK: - Sorted entries

    func testSortedEntriesIncludesAllEvents() {
        let now = Date()
        let old = now.addingTimeInterval(-25 * 60 * 60)

        let events = [
            GestureEvent(gesture: "Old Gesture", timestamp: old, fired: false),
            GestureEvent(gesture: "Recent Gesture", timestamp: now, fired: true),
        ]
        let stats = makeStats(events)

        let entries = stats.sortedEntries
        XCTAssertEqual(entries.count, 2)
    }

    func testSortedEntriesAggregatesByGesture() {
        let now = Date()
        let events = [
            GestureEvent(gesture: "4 Finger Tap", timestamp: now.addingTimeInterval(-100), fired: false),
            GestureEvent(gesture: "4 Finger Tap", timestamp: now.addingTimeInterval(-50), fired: true),
            GestureEvent(gesture: "3 Finger Tap", timestamp: now.addingTimeInterval(-30), fired: false),
        ]
        let stats = makeStats(events)

        let entries = stats.sortedEntries
        XCTAssertEqual(entries.count, 2)

        let fourFinger = entries.first { $0.gesture == "4 Finger Tap" }
        XCTAssertEqual(fourFinger?.totalCount, 2)
        XCTAssertEqual(fourFinger?.firedCount, 1)

        let threeFinger = entries.first { $0.gesture == "3 Finger Tap" }
        XCTAssertEqual(threeFinger?.totalCount, 1)
        XCTAssertEqual(threeFinger?.firedCount, 0)
    }

    func testSortedEntriesSortedByCount() {
        let now = Date()
        let events = [
            GestureEvent(gesture: "Rare", timestamp: now, fired: false),
            GestureEvent(gesture: "Common", timestamp: now, fired: false),
            GestureEvent(gesture: "Common", timestamp: now, fired: false),
            GestureEvent(gesture: "Common", timestamp: now, fired: false),
        ]
        let stats = makeStats(events)

        let entries = stats.sortedEntries
        XCTAssertEqual(entries.first?.gesture, "Common")
        XCTAssertEqual(entries.last?.gesture, "Rare")
    }

    func testSortedEntriesLastDetectedIsLatestTimestamp() {
        let now = Date()
        let earlier = now.addingTimeInterval(-600)
        let events = [
            GestureEvent(gesture: "Tap", timestamp: earlier, fired: false),
            GestureEvent(gesture: "Tap", timestamp: now, fired: false),
        ]
        let stats = makeStats(events)

        let entry = stats.sortedEntries.first
        XCTAssertNotNil(entry?.lastDetected)
        XCTAssertEqual(entry?.lastDetected?.timeIntervalSince1970 ?? 0, now.timeIntervalSince1970, accuracy: 1.0)
    }

    // MARK: - Unique gestures count

    func testUniqueGesturesCount() {
        let now = Date()
        let events = [
            GestureEvent(gesture: "A", timestamp: now, fired: false),
            GestureEvent(gesture: "B", timestamp: now, fired: false),
            GestureEvent(gesture: "A", timestamp: now, fired: false), // duplicate
        ]
        let stats = makeStats(events)

        XCTAssertEqual(stats.uniqueGesturesCount, 2)
    }

    // MARK: - All-time totals

    func testAllTimeTotalsIncludeOldEvents() {
        let old = Date().addingTimeInterval(-25 * 60 * 60)
        let events = [
            GestureEvent(gesture: "Old", timestamp: old, fired: false),
        ]
        let stats = makeStats(events, total: 50, fired: 30)

        XCTAssertEqual(stats.totalGestures, 50)
        XCTAssertEqual(stats.totalFired, 30)
        XCTAssertEqual(stats.unmatchedCount, 20)
        // Old events are still in the breakdown
        XCTAssertEqual(stats.sortedEntries.count, 1)
        XCTAssertEqual(stats.sortedEntries.first?.gesture, "Old")
    }

    // MARK: - GestureEvent Codable

    func testGestureEventCodableRoundTrip() throws {
        let event = GestureEvent(gesture: "Circle Clockwise", timestamp: Date(), fired: true)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(GestureEvent.self, from: data)

        XCTAssertEqual(decoded.gesture, "Circle Clockwise")
        XCTAssertTrue(decoded.fired)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, event.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Empty state

    func testEmptyStatsDefaults() {
        let stats = makeStats()

        XCTAssertEqual(stats.totalGestures, 0)
        XCTAssertEqual(stats.totalFired, 0)
        XCTAssertEqual(stats.unmatchedCount, 0)
        XCTAssertTrue(stats.events.isEmpty)
        XCTAssertTrue(stats.sortedEntries.isEmpty)
        XCTAssertEqual(stats.uniqueGesturesCount, 0)
    }
}
