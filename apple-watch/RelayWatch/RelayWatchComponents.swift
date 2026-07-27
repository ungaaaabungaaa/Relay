import SwiftUI

struct RelayAdaptiveContainer<Compact: View, Scrolling: View>: View {
    private let compact: Compact
    private let scrolling: Scrolling

    init(
        @ViewBuilder compact: () -> Compact,
        @ViewBuilder scrolling: () -> Scrolling
    ) {
        self.compact = compact()
        self.scrolling = scrolling()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            compact
            ScrollView(.vertical) {
                scrolling
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct RelayMaterialTile: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: RelayCompactLayout.materialTileMinimumHeight
            )
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: RelayWatchStyle.tileCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct RelayActionDock: View {
    let primaryTitle: String
    let secondaryTitle: String
    let primary: () -> Void
    let secondary: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(primaryTitle, action: primary)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(primaryTitle)
            Button(secondaryTitle, action: secondary)
                .buttonStyle(.plain)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(.thinMaterial, in: Capsule())
                .accessibilityLabel(secondaryTitle)
        }
    }
}

struct RelayStatusStrip: View {
    let connection: RelayConnectionState
    let cacheIsStale: Bool
    let error: String?

    var body: some View {
        let presentation = RelayStatusPresentation.make(
            connection: connection,
            cacheIsStale: cacheIsStale,
            error: error
        )
        VStack(alignment: .leading, spacing: 3) {
            Label(presentation.title, systemImage: presentation.systemImage)
                .font(.caption2.weight(.medium))
            if let detail = presentation.detail {
                Text(detail)
                    .font(.caption2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(color(for: presentation.tone))
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func color(for tone: RelayStatusPresentation.Tone) -> Color {
        switch tone {
        case .normal: RelayWatchStyle.foreground
        case .attention: .orange
        case .destructive: .red
        }
    }
}
