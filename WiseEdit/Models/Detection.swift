import Foundation

enum DetectionKind: String, Codable, CaseIterable, Hashable {
    case filler
    case retake
    case silence

    var title: String {
        switch self {
        case .filler: return "Filler words"
        case .retake: return "Re-takes"
        case .silence: return "Long pauses"
        }
    }

    var symbol: String {
        switch self {
        case .filler: return "text.bubble"
        case .retake: return "arrow.triangle.2.circlepath"
        case .silence: return "pause.circle"
        }
    }
}

/// A single AI suggestion the user can accept or reject in the Review panel.
/// Filler/retake suggestions delete words; silence suggestions tighten a pause.
struct Detection: Identifiable, Hashable {
    let id = UUID()
    var kind: DetectionKind
    var wordIDs: [UUID]
    var label: String
    /// Source-time start (seconds) for jump-to.
    var startTime: Double
    var clipID: UUID
    /// Gap length for silence suggestions.
    var gap: Double = 0
    var accepted: Bool = true
}

/// Lowercases and strips edge punctuation for matching/comparison.
enum TextNormalize {
    static func word(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}
