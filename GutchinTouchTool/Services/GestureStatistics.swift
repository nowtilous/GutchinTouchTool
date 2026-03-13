import Foundation

struct GestureEvent: Codable {
    let gesture: String
    let timestamp: Date
    let fired: Bool
}

struct GestureStatEntry: Identifiable {
    var id: String { gesture }
    let gesture: String
    var totalCount: Int
    var firedCount: Int
    var lastDetected: Date?
}

@MainActor
class GestureStatistics: ObservableObject {
    static let shared = GestureStatistics()

    @Published var totalGestures: Int = 0
    @Published var totalFired: Int = 0
    @Published var sessionStart: Date = Date()
    @Published private(set) var events: [GestureEvent] = []

    private let storageKey = "GTTGestureStatistics"
    private let sessionStartKey = "GTTSessionStart"
    private let eventsKey = "GTTGestureEvents"

    private init() {
        load()
    }

    /// Test-only initializer — creates an isolated instance that does not touch UserDefaults
    init(testEvents: [GestureEvent], totalGestures: Int = 0, totalFired: Int = 0) {
        self.events = testEvents
        self.totalGestures = totalGestures
        self.totalFired = totalFired
        self.sessionStart = Date()
    }

    func recordDetection(_ gesture: String) {
        totalGestures += 1
        events.append(GestureEvent(gesture: gesture, timestamp: Date(), fired: false))
        save()
    }

    func recordFire(_ gesture: String) {
        totalFired += 1
        events.append(GestureEvent(gesture: gesture, timestamp: Date(), fired: true))
        save()
    }

    nonisolated func recordDetectionFromAnyThread(_ gesture: String) {
        Task { @MainActor in self.recordDetection(gesture) }
    }

    nonisolated func recordFireFromAnyThread(_ gesture: String) {
        Task { @MainActor in self.recordFire(gesture) }
    }

    func reset() {
        totalGestures = 0
        totalFired = 0
        events = []
        sessionStart = Date()
        save()
    }

    var unmatchedCount: Int {
        totalGestures - totalFired
    }

    var sortedEntries: [GestureStatEntry] {
        var map: [String: GestureStatEntry] = [:]
        for event in events {
            var entry = map[event.gesture] ?? GestureStatEntry(gesture: event.gesture, totalCount: 0, firedCount: 0)
            entry = GestureStatEntry(
                gesture: entry.gesture,
                totalCount: entry.totalCount + 1,
                firedCount: entry.firedCount + (event.fired ? 1 : 0),
                lastDetected: event.timestamp
            )
            map[event.gesture] = entry
        }
        return map.values.sorted { $0.totalCount > $1.totalCount }
    }

    var uniqueGesturesCount: Int {
        Set(events.map(\.gesture)).count
    }

    private func save() {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: eventsKey)
        }
        UserDefaults.standard.set(totalGestures, forKey: "\(storageKey)_total")
        UserDefaults.standard.set(totalFired, forKey: "\(storageKey)_fired")
        UserDefaults.standard.set(sessionStart.timeIntervalSince1970, forKey: sessionStartKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: eventsKey),
           let saved = try? JSONDecoder().decode([GestureEvent].self, from: data) {
            events = saved
        }
        totalGestures = UserDefaults.standard.integer(forKey: "\(storageKey)_total")
        totalFired = UserDefaults.standard.integer(forKey: "\(storageKey)_fired")
        let ts = UserDefaults.standard.double(forKey: sessionStartKey)
        sessionStart = ts > 0 ? Date(timeIntervalSince1970: ts) : Date()
    }
}
