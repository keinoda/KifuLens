import SwiftUI

enum KifuLensTheme {
    static let background = Color(red: 0.035, green: 0.050, blue: 0.055)
    static let backgroundRaised = Color(red: 0.055, green: 0.075, blue: 0.082)
    static let surface = Color(red: 0.075, green: 0.100, blue: 0.108)
    static let surfaceRaised = Color(red: 0.105, green: 0.135, blue: 0.145)
    static let surfaceSelected = Color(red: 0.145, green: 0.190, blue: 0.205)

    static let primaryText = Color.white.opacity(0.96)
    static let secondaryText = Color.white.opacity(0.60)
    static let tertiaryText = Color.white.opacity(0.52)
    static let divider = Color.white.opacity(0.10)

    static let accent = Color(red: 0.98, green: 0.61, blue: 0.18)
    static let accentSoft = Color(red: 0.48, green: 0.31, blue: 0.12)
    static let positive = Color(red: 0.27, green: 0.78, blue: 0.61)
    static let neutral = Color(red: 0.72, green: 0.76, blue: 0.78)
    static let negative = Color(red: 0.96, green: 0.34, blue: 0.31)
    static let selection = Color(red: 0.24, green: 0.78, blue: 0.53)

    static let boardFrame = Color(red: 0.17, green: 0.105, blue: 0.050)
    static let boardInk = Color.black.opacity(0.72)
}

struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                KifuLensTheme.backgroundRaised,
                KifuLensTheme.background,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

struct PanelSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(KifuLensTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(KifuLensTheme.divider, lineWidth: 1)
            }
    }
}

extension View {
    func panelSurface() -> some View {
        modifier(PanelSurface())
    }
}
