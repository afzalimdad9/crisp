import Foundation

extension Double {
    /// Formats a duration in seconds as `m:ss` or `h:mm:ss`.
    var timecodeString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
