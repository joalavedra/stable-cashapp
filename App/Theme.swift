import SwiftUI

/// Cash App–style palette and shared styling.
enum Theme {
    /// Cash App signature green.
    static let green = Color(red: 0.0, green: 0.84, blue: 0.20)        // #00D632
    static let greenDark = Color(red: 0.0, green: 0.66, blue: 0.18)
    static let ink = Color(red: 0.07, green: 0.08, blue: 0.09)         // near-black
    static let surface = Color(red: 0.96, green: 0.97, blue: 0.97)
    static let subtle = Color(red: 0.45, green: 0.47, blue: 0.50)
    static let hairline = Color.black.opacity(0.06)
}

extension Font {
    /// The oversized rounded amount display Cash App uses on its home screen.
    static func amount(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

/// Big pill button used for primary actions ("Pay", "Confirm").
struct PrimaryButtonStyle: ButtonStyle {
    var filled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .semibold, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(filled ? Color.white : Theme.ink)
            .background(filled ? Theme.green : Theme.surface)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
