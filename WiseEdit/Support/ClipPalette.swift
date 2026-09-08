import SwiftUI

/// Distinct colors for clips on the timeline and in the bin.
enum ClipPalette {
    static let colors: [Color] = [
        Color(red: 0.36, green: 0.55, blue: 0.96),  // blue
        Color(red: 0.61, green: 0.40, blue: 0.93),  // purple
        Color(red: 0.95, green: 0.45, blue: 0.62),  // pink
        Color(red: 0.96, green: 0.62, blue: 0.30),  // orange
        Color(red: 0.27, green: 0.74, blue: 0.69),  // teal
        Color(red: 0.45, green: 0.74, blue: 0.42),  // green
    ]

    static func color(for index: Int) -> Color {
        colors[((index % colors.count) + colors.count) % colors.count]
    }
}
