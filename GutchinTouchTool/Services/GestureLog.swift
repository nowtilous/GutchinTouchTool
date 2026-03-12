import Foundation

enum LogLevel {
    case detect   // gesture detected (blue)
    case fire     // trigger matched & fired (green)
    case action   // action being executed (orange)
    case noMatch  // gesture with no trigger (gray)
    case error    // something went wrong (red)
}

struct GestureLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let level: LogLevel
}

@MainActor
class GestureLog: ObservableObject {
    static let shared = GestureLog()

    @Published var entries: [GestureLogEntry] = []

    func log(_ message: String, level: LogLevel = .detect) {
        let entry = GestureLogEntry(timestamp: Date(), message: message, level: level)
        entries.append(entry)
        if entries.count > 50 {
            entries.removeFirst(entries.count - 50)
        }
    }

    nonisolated func logFromAnyThread(_ message: String, level: LogLevel = .detect) {
        Task { @MainActor in
            self.log(message, level: level)
        }
    }
}
