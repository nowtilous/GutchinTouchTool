import Foundation

class PresetManager {
    private static let defaultDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GutchinTouchTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

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

    static func loadPreset() -> Preset? {
        let url = defaultDirectory.appendingPathComponent("master_preset.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Preset.self, from: data)
        } catch {
            print("Failed to load preset: \(error)")
            return nil
        }
    }

    func loadPreset() -> Preset? {
        guard FileManager.default.fileExists(atPath: masterPresetURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: masterPresetURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Preset.self, from: data)
        } catch {
            print("Failed to load preset: \(error)")
            return nil
        }
    }

    func save(_ preset: Preset) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(preset)
            try data.write(to: masterPresetURL, options: .atomic)
        } catch {
            print("Failed to save preset: \(error)")
        }
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
