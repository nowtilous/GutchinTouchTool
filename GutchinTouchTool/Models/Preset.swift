import Foundation

/// Absorbs any JSON value — used to skip broken entries during resilient decoding.
private struct AnyCodable: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if let _ = try? container.decode(Bool.self) { return }
        if let _ = try? container.decode(Int.self) { return }
        if let _ = try? container.decode(Double.self) { return }
        if let _ = try? container.decode(String.self) { return }
        if let _ = try? container.decode([AnyCodable].self) { return }
        if let _ = try? container.decode([String: AnyCodable].self) { return }
    }
    func encode(to encoder: Encoder) throws {}
}

struct Preset: Identifiable, Codable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var isMaster: Bool
    var triggers: [Trigger]
    var appTargets: [AppTarget]
    var createdAt: Date
    var modifiedAt: Date

    // Resilient decoding: skip triggers that fail to decode (e.g. renamed gestures)
    // instead of failing the entire preset load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        isMaster = try container.decode(Bool.self, forKey: .isMaster)
        appTargets = try container.decode([AppTarget].self, forKey: .appTargets)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)

        // Decode triggers one-by-one, skipping any that fail
        var triggersContainer = try container.nestedUnkeyedContainer(forKey: .triggers)
        var decodedTriggers: [Trigger] = []
        while !triggersContainer.isAtEnd {
            if let trigger = try? triggersContainer.decode(Trigger.self) {
                decodedTriggers.append(trigger)
            } else {
                // Skip the broken entry by decoding it as a generic JSON object
                _ = try? triggersContainer.decode(AnyCodable.self)
            }
        }
        triggers = decodedTriggers
        if decodedTriggers.count < (try? container.decode([AnyCodable].self, forKey: .triggers))?.count ?? 0 {
            NSLog("[PresetManager] Warning: some triggers were skipped due to decode errors")
        }
    }

    init(name: String, isMaster: Bool = false) {
        self.id = UUID()
        self.name = name
        self.isEnabled = true
        self.isMaster = isMaster
        self.triggers = []
        self.appTargets = [.allApps]
        self.createdAt = Date()
        self.modifiedAt = Date()
    }

    func triggers(for appTarget: AppTarget, category: TriggerCategory) -> [Trigger] {
        triggers.filter { trigger in
            trigger.input.category == category &&
            trigger.appBundleID == appTarget.bundleID
        }.sorted { $0.order < $1.order }
    }

    mutating func addTrigger(_ trigger: Trigger) {
        triggers.append(trigger)
        modifiedAt = Date()
    }

    mutating func removeTrigger(id: UUID) {
        triggers.removeAll { $0.id == id }
        modifiedAt = Date()
    }

    mutating func updateTrigger(_ trigger: Trigger) {
        if let index = triggers.firstIndex(where: { $0.id == trigger.id }) {
            triggers[index] = trigger
            modifiedAt = Date()
        }
    }
}
