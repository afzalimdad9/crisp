import AVFoundation
import AppKit

/// Generates a small poster frame for a clip (used in the media bin).
enum Thumbnailer {
    static func generate(url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)
        let time = CMTime(seconds: 1, preferredTimescale: 600)
        guard let result = try? await generator.image(at: time) else { return nil }
        return NSImage(cgImage: result.image, size: .zero)
    }
}
