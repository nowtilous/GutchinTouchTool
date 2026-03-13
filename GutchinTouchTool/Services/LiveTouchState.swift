import Foundation

extension Notification.Name {
    static let gestureDidFire = Notification.Name("GTTGestureDidFire")
}

struct TouchPoint: Identifiable {
    let id: Int
    var x: Float
    var y: Float
    var size: Float
}

struct TrailPoint {
    var x: Float
    var y: Float
    var age: TimeInterval // seconds since creation
}

@MainActor
class LiveTouchState: ObservableObject {
    static let shared = LiveTouchState()
    @Published var touches: [TouchPoint] = []
    @Published var isPressed: Bool = false
    @Published var lastFiredTriggerID: UUID?

    /// Trail history per finger ID — each finger gets a list of recent positions
    @Published var trails: [Int: [TrailPoint]] = [:]
    private let maxTrailAge: TimeInterval = 0.6
    private let maxTrailPoints: Int = 40
    private var fadeTimer: Timer?

    nonisolated func update(_ points: [TouchPoint]) {
        Task { @MainActor in
            self.touches = points

            // Clear press state when all fingers lift
            if points.isEmpty && self.isPressed {
                self.isPressed = false
            }

            let now = ProcessInfo.processInfo.systemUptime
            let activeIDs = Set(points.map { $0.id })

            // Append new positions to trails
            for point in points {
                var trail = self.trails[point.id] ?? []
                trail.append(TrailPoint(x: point.x, y: point.y, age: now))
                // Keep trail bounded
                if trail.count > self.maxTrailPoints {
                    trail.removeFirst(trail.count - self.maxTrailPoints)
                }
                self.trails[point.id] = trail
            }

            // Age out old points and remove stale trails
            for (fingerID, trail) in self.trails {
                if !activeIDs.contains(fingerID) {
                    let filtered = trail.filter { now - $0.age < self.maxTrailAge }
                    if filtered.isEmpty {
                        self.trails.removeValue(forKey: fingerID)
                    } else {
                        self.trails[fingerID] = filtered
                    }
                }
            }

            // Start fade timer when there are trails but no active touches
            self.updateFadeTimer()
        }
    }

    private func updateFadeTimer() {
        if !trails.isEmpty && touches.isEmpty {
            // Need continuous fade — start timer if not running
            if fadeTimer == nil {
                fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.tickFade()
                    }
                }
            }
        } else if trails.isEmpty {
            fadeTimer?.invalidate()
            fadeTimer = nil
        }
    }

    private func tickFade() {
        let now = ProcessInfo.processInfo.systemUptime
        var changed = false
        for (fingerID, trail) in trails {
            let filtered = trail.filter { now - $0.age < maxTrailAge }
            if filtered.count != trail.count {
                changed = true
                if filtered.isEmpty {
                    trails.removeValue(forKey: fingerID)
                } else {
                    trails[fingerID] = filtered
                }
            }
        }
        if trails.isEmpty {
            fadeTimer?.invalidate()
            fadeTimer = nil
        } else if changed {
            // Force publish change so Canvas redraws
            objectWillChange.send()
        }
    }

    nonisolated func setPressed(_ pressed: Bool) {
        Task { @MainActor in
            self.isPressed = pressed
        }
    }

    nonisolated func flashTrigger(_ id: UUID) {
        Task { @MainActor in
            self.lastFiredTriggerID = id
            try? await Task.sleep(nanoseconds: 600_000_000)
            if self.lastFiredTriggerID == id {
                self.lastFiredTriggerID = nil
            }
        }
    }
}
