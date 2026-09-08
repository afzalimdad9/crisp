import Foundation
import Observation

/// Where transcription runs. `auto` prefers on-device when the Mac can run the
/// model, otherwise falls back to the cloud (when available + signed in).
enum ProcessingMode: String, Codable, CaseIterable, Identifiable {
    case auto
    case onDevice
    case cloud

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:     return "Automatic"
        case .onDevice: return "On-device"
        case .cloud:    return "Cloud"
        }
    }
}

/// User-configurable settings, persisted to UserDefaults.
struct AppSettings: Equatable {
    var modelName: String = "large-v3-v20240930_turbo"
    var silenceThreshold: Double = 0.6   // gaps longer than this are flagged (s)
    var retakeThreshold: Double = 0.8    // similarity needed to call it a re-take
    var fillerTerms: [String] = AppSettings.defaultFillerTerms
    /// Auto-scroll the transcript to follow playback.
    var followAlong: Bool = true
    /// Where transcription runs (on-device today; cloud added in a later phase).
    var processingMode: ProcessingMode = .auto
    /// Whether the user has consented to uploading audio for cloud transcription.
    var cloudConsentGiven: Bool = false

    static let defaultFillerTerms = [
        "um", "uh", "uhh", "umm", "er", "erm", "ah", "hmm", "mm",
        "basically", "literally", "actually",
        "you know", "i mean", "sort of", "kind of",
    ]

    /// A term containing a space is treated as a phrase, otherwise a single word.
    var fillerConfig: FillerConfig {
        FillerConfig(
            singleWords: fillerTerms.filter { !$0.contains(" ") },
            phrases: fillerTerms.filter { $0.contains(" ") })
    }
}

// Resilient decoding: missing keys fall back to defaults, so adding new settings
// never wipes a user's existing preferences.
extension AppSettings: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName) ?? modelName
        silenceThreshold = try c.decodeIfPresent(Double.self, forKey: .silenceThreshold) ?? silenceThreshold
        retakeThreshold = try c.decodeIfPresent(Double.self, forKey: .retakeThreshold) ?? retakeThreshold
        fillerTerms = try c.decodeIfPresent([String].self, forKey: .fillerTerms) ?? fillerTerms
        followAlong = try c.decodeIfPresent(Bool.self, forKey: .followAlong) ?? followAlong
        processingMode = try c.decodeIfPresent(ProcessingMode.self, forKey: .processingMode) ?? processingMode
        cloudConsentGiven = try c.decodeIfPresent(Bool.self, forKey: .cloudConsentGiven) ?? cloudConsentGiven
    }
}

/// Observable, auto-persisting settings store.
@Observable
@MainActor
final class SettingsStore {
    private static let key = "WiseEditSettings"

    var settings: AppSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
        }
    }

    func resetFillers() {
        settings.fillerTerms = AppSettings.defaultFillerTerms
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
