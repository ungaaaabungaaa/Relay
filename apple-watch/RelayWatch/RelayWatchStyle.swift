import SwiftUI

enum RelayWatchStyle {
    static let accent = Color.blue
    static let foreground = Color.primary
    static let secondaryForeground = Color.secondary
    static let surface = Material.thin
    static let tileCornerRadius: CGFloat = 16
}

struct RelayWatchMark: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(.primary)
                .frame(width: 30, height: 7)
                .offset(y: 7)

            Ellipse()
                .fill(.primary.opacity(0.9))
                .frame(width: 18, height: 10)
                .offset(y: 2)

            Capsule()
                .strokeBorder(.primary.opacity(0.55), lineWidth: 1)
                .frame(width: 35, height: 11)
                .offset(y: 7)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Relay")
    }
}
