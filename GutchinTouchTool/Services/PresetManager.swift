import Foundation

class PresetManager {
    private static let presetsDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("GutchinTouchTool", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let masterPresetURL: URL = {
        presetsDirectory.appendingPathComponent("master_preset.json")
    }()

    static func loadPreset() -> Preset? {
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
            try data.write(to: Self.masterPresetURL, options: .atomic)
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
