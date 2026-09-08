import SwiftUI

/// Central design tokens for the editor's dark "studio" look. The app runs in a
/// fixed dark appearance (like every pro NLE), so these are concrete sRGB colors
/// rather than dynamic system colors — that keeps the chrome cohesive and the
/// video the brightest thing on screen.
enum Theme {
    // MARK: Brand
    /// Matches Assets/AccentColor so `Color.accentColor` and `Theme.accent` agree.
    static let accent      = Color(red: 0.451, green: 0.353, blue: 0.937)
    static let accentSoft  = Color(red: 0.451, green: 0.353, blue: 0.937).opacity(0.22)

    // MARK: Surfaces (deep → light)
    /// The window background, gutters between panels, timeline tray.
    static let window      = Color(red: 0.055, green: 0.059, blue: 0.074)
    /// Panel bodies (library, transcript, review).
    static let panel       = Color(red: 0.094, green: 0.100, blue: 0.122)
    /// Header bars, transport, rows/cards resting on a panel.
    static let elevated    = Color(red: 0.140, green: 0.148, blue: 0.176)
    /// Hover/highlight fill for interactive rows.
    static let elevatedHi  = Color(red: 0.180, green: 0.190, blue: 0.224)
    /// The matte around the video monitor (nearly black).
    static let stage       = Color(red: 0.020, green: 0.022, blue: 0.030)

    // MARK: Lines
    static let hairline    = Color.white.opacity(0.07)
    static let stroke      = Color.white.opacity(0.12)

    // MARK: Text
    static let textPrimary   = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.56)
    static let textTertiary  = Color.white.opacity(0.34)

    // MARK: Semantic (transcript flags / detections)
    static let filler = Color(red: 0.98, green: 0.66, blue: 0.30)
    static let retake = Color(red: 0.97, green: 0.44, blue: 0.46)
    static let pause  = Color(red: 0.40, green: 0.72, blue: 0.99)

    // MARK: Metrics
    static let cardRadius: CGFloat  = 9
    static let chipRadius: CGFloat  = 5
    static let headerHeight: CGFloat = 38
}

/// A consistent panel title bar: small uppercase caption on the elevated surface
/// with a bottom hairline, plus an optional trailing control cluster.
struct PanelHeader<Trailing: View>: View {
    let title: String
    var systemImage: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.headerHeight)
        .frame(maxWidth: .infinity)
        .background(Theme.elevated)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

extension PanelHeader where Trailing == EmptyView {
    init(title: String, systemImage: String? = nil) {
        self.init(title: title, systemImage: systemImage) { EmptyView() }
    }
}

extension View {
    /// A soft, slow accent glow used to draw the eye to the next action (e.g. the
    /// Apply button once Auto-clean has produced suggestions).
    func attentionPulse(_ active: Bool, color: Color = Theme.accent) -> some View {
        modifier(AttentionPulse(active: active, color: color))
    }
}

private struct AttentionPulse: ViewModifier {
    let active: Bool
    let color: Color
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .shadow(color: (active && on) ? color.opacity(0.75) : .clear,
                    radius: (active && on) ? 12 : 0)
            .animation(active ? .easeInOut(duration: 1.1).repeatForever(autoreverses: true) : .default,
                       value: on)
            .onAppear { on = active }
            .onChange(of: active) { _, newValue in on = newValue }
    }
}
