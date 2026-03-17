import Foundation

class PresetManager {
    private static let defaultDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GutchinTouchTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var backupDirectory: URL {
        if let custom = UserDefaults.standard.string(forKey: "GTTBackupPath"),
           !custom.isEmpty {
            let url = URL(fileURLWithPath: custom, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".gutchintouchtool_backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var backupsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "GTTBackupsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "GTTBackupsEnabled") }
    }

    /// Maximum number of rolling backups to keep
    static var maxBackups: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: "GTTMaxBackups")
            return stored > 0 ? stored : 5
        }
        set { UserDefaults.standard.set(newValue, forKey: "GTTMaxBackups") }
    }

    /// Returns info about existing backups (date and file size)
    static func listBackups() -> [(date: Date, size: Int64, url: URL)] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
                .filter { $0.pathExtension == "json" }
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return da > db
                }
            return files.compactMap { url in
                let vals = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                let date = vals?.creationDate ?? .distantPast
                let size = Int64(vals?.fileSize ?? 0)
                return (date: date, size: size, url: url)
            }
        } catch {
            return []
        }
    }

    static var presetFilePath: String {
        defaultDirectory.appendingPathComponent("master_preset.json").path
    }

    private let presetsDirectory: URL
    private var masterPresetURL: URL {
        presetsDirectory.appendingPathComponent("master_preset.json")
    }

    init(directory: URL? = nil) {
        if let dir = directory {
            self.presetsDirectory = dir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } else {
            self.presetsDirectory = Self.defaultDirectory
        }
    }

    // MARK: - Backup

    /// All UserDefaults keys used by the app
    private static let userDefaultsKeys: [String] = {
        var keys = [
            "GTTGlobalEnabled",
            "GTTAccentColor",
            "GTTAppearance",
            "GTTPressDragThreshold",
            "GTTTipTapMinRestTime",
            "GTTSuppressMouseDuringDrawing",
            "launchAtLogin",
            "showMenuBarIcon"
        ]
        // Add per-gesture swipe velocity keys
        for gesture in TrackpadGesture.allCases {
            keys.append("GTTSwipeMinVelocity_\(gesture.rawValue)")
        }
        return keys
    }()

    private static func saveBackup(data: Data) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let backupURL = backupDirectory.appendingPathComponent("preset_backup_\(timestamp).json")
        do {
            try data.write(to: backupURL, options: .atomic)
            NSLog("[GTT] Backup saved to %@", backupURL.path)
            pruneOldBackups()
        } catch {
            NSLog("[GTT] Failed to save backup: %@", error.localizedDescription)
        }
        // Also back up UserDefaults
        saveUserDefaultsBackup()
    }

    private static func saveUserDefaultsBackup() {
        var dict: [String: Any] = [:]
        for key in userDefaultsKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                dict[key] = value
            }
        }
        guard !dict.isEmpty else { return }
        let url = backupDirectory.appendingPathComponent("settings_backup.plist")
        (dict as NSDictionary).write(to: url, atomically: true)
    }

    static func restoreUserDefaultsFromBackup() {
        let url = backupDirectory.appendingPathComponent("settings_backup.plist")
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return }
        NSLog("[GTT] Restoring UserDefaults from backup (%d keys)", dict.count)
        for (key, value) in dict {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    private static func pruneOldBackups() {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "json" }
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return da > db // newest first
                }
            if files.count > maxBackups {
                for file in files.dropFirst(maxBackups) {
                    try? FileManager.default.removeItem(at: file)
                    NSLog("[GTT] Pruned old backup: %@", file.lastPathComponent)
                }
            }
        } catch {
            NSLog("[GTT] Failed to prune backups: %@", error.localizedDescription)
        }
    }

    /// Returns the most recent backup, if any.
    static func loadLatestBackup() -> Preset? {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "json" }
                .sorted { a, b in
                    let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return da > db
                }
            guard let latest = files.first else { return nil }
            NSLog("[GTT] Restoring from backup: %@", latest.path)
            let data = try Data(contentsOf: latest)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Preset.self, from: data)
        } catch {
            NSLog("[GTT] Failed to load backup: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Load

    static func loadPreset() -> Preset? {
        let url = defaultDirectory.appendingPathComponent("master_preset.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(Preset.self, from: data)
            } catch {
                print("Failed to load preset: \(error)")
            }
        }
        // Primary file missing or corrupt — try restoring from backup
        if let backup = loadLatestBackup() {
            NSLog("[GTT] Primary preset missing — restored from backup with %d triggers", backup.triggers.count)
            // Re-save to primary location so it's back in place
            let manager = PresetManager()
            manager.save(backup, createBackup: false)
            return backup
        }
        return nil
    }

    func loadPreset() -> Preset? {
        if FileManager.default.fileExists(atPath: masterPresetURL.path) {
            do {
                let data = try Data(contentsOf: masterPresetURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(Preset.self, from: data)
            } catch {
                print("Failed to load preset: \(error)")
            }
        }
        return Self.loadLatestBackup()
    }

    // MARK: - Save

    func save(_ preset: Preset, createBackup: Bool = true) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preset)
            try data.write(to: masterPresetURL, options: .atomic)
            if createBackup {
                Self.saveBackup(data: data)
            }
        } catch {
            print("Failed to save preset: \(error)")
        }
    }

    func save(_ preset: Preset) {
        save(preset, createBackup: Self.backupsEnabled)
    }

    func exportPreset(_ preset: Preset, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preset)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to export preset: \(error)")
        }
    }

    func importPreset(from url: URL) -> Preset? {
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Preset.self, from: data)
        } catch {
            print("Failed to import preset: \(error)")
            return nil
        }
    }
}
