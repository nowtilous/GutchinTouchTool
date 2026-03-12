import Foundation

struct Preset: Identifiable, Codable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var isMaster: Bool
    var triggers: [Trigger]
    var appTargets: [AppTarget]
    var createdAt: Date
    var modifiedAt: Date

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
