import SwiftUI

struct RelayUFOGlyph: View {
    var body: some View {
        ZStack {
            Capsule()
                .fill(.primary)
                .frame(width: 22, height: 5)
                .offset(y: 5)

            Ellipse()
                .fill(.primary.opacity(0.9))
                .frame(width: 13, height: 7)
                .offset(y: 1)

            Capsule()
                .strokeBorder(.primary.opacity(0.55), lineWidth: 1)
                .frame(width: 26, height: 8)
                .offset(y: 5)
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Relay UFO")
    }
}

struct RelayBrandMark: View {
    var body: some View {
        HStack(spacing: 9) {
            RelayUFOGlyph()
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
