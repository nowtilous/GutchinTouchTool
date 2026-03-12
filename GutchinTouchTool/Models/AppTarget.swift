import Foundation
import AppKit

struct AppTarget: Identifiable, Codable, Hashable {
    let id: UUID
    var bundleID: String?
    var name: String
    var iconPath: String?

    var isGlobal: Bool { bundleID == nil }

    static let allApps = AppTarget(id: UUID(), bundleID: nil, name: "All Apps", iconPath: nil)

    var icon: NSImage? {
        if isGlobal {
            return NSImage(systemSymbolName: "globe", accessibilityDescription: "All Apps")
        }
        if let bundleID = bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "app", accessibilityDescription: name)
    }
}
