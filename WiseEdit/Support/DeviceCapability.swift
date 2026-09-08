import Foundation

/// Lightweight check for whether this Mac can comfortably run the on-device
/// Whisper model. Used to recommend the cloud path on Intel / low-RAM Macs.
enum DeviceCapability {
    /// True on Apple-Silicon Macs with enough memory for the large model.
    static var canRunLocalModel: Bool {
        isAppleSilicon && physicalMemoryGB >= 8
    }

    static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    /// Installed physical memory in GiB.
    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    /// A short, user-facing note about the recommended transcription path.
    static var recommendation: String {
        canRunLocalModel
            ? "This Mac can run transcription on-device — free, private, and offline."
            : "This Mac may struggle with on-device transcription; cloud is recommended (coming soon)."
    }
}
