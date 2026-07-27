import SwiftUI

struct RelayUFOGlyph: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Capsule()
                .fill(.primary)
                .frame(width: size * 0.85, height: size * 0.2)
                .offset(y: size * 0.16)

            Ellipse()
                .fill(.primary.opacity(0.9))
                .frame(width: size * 0.5, height: size * 0.28)
                .offset(y: -size * 0.06)

            Capsule()
                .strokeBorder(.primary.opacity(0.55), lineWidth: 1)
                .frame(width: size, height: size * 0.36)
                .offset(y: size * 0.16)
        }
        .frame(width: size, height: size)
        .foregroundStyle(.primary)
        .accessibilityLabel("Relay")
    }
}

struct RelayBrandMark: View {
    var body: some View {
        HStack(spacing: 9) {
            RelayUFOGlyph(size: 26)
                .frame(width: 30, height: 22)
                .accessibilityHidden(true)
            Text("Relay")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Relay")
    }
}
