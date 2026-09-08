import Foundation

/// App-wide configuration. The cloud API base URL defaults to production but can
/// be overridden (e.g. to a local backend) via the `apiBaseURL` UserDefaults key:
///   defaults write com.wisedt.WiseEdit apiBaseURL http://localhost:8787
enum AppConfig {
    static var apiBaseURL: URL {
        if let s = UserDefaults.standard.string(forKey: "apiBaseURL"),
           let url = URL(string: s) {
            return url
        }
        // Live Vercel service. Swap to the custom domain (crisp-api-afzalimdad9.vercel.app)
        // once a CNAME is pointed at it.
        return URL(string: "https://crisp-api-afzalimdad9.vercel.app")!
    }
}
