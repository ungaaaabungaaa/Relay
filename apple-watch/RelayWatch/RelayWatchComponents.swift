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
        }
    }
}

struct RelayMaterialTile: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(8)
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
        Label(statusTitle, systemImage: statusSymbol)
            .font(.caption2.weight(.medium))
            .foregroundStyle(statusColor)
            .lineLimit(1)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .background(.thinMaterial, in: Capsule())
            .accessibilityLabel(statusTitle)
            .accessibilityHint(error ?? "")
    }

    private var statusTitle: String {
        if let error { return error }
        if connection == .offline || cacheIsStale { return "Mac offline · cached data" }
        switch connection {
        case .live: return "Relay live"
        case .unpaired: return "Pair with Mac"
        case .pairing: return "Pairing with Mac"
        case .revoked: return "Access revoked"
        case .incompatible: return "Update required"
        case .offline: return "Mac offline · cached data"
        }
    }

    private var statusSymbol: String {
        if error != nil { return "exclamationmark.triangle.fill" }
        if connection == .offline || cacheIsStale { return "wifi.slash" }
        switch connection {
        case .live: return "checkmark.circle.fill"
        case .unpaired, .pairing: return "link"
        case .revoked: return "lock.slash"
        case .incompatible: return "arrow.triangle.2.circlepath"
        case .offline: return "wifi.slash"
        }
    }

    private var statusColor: Color {
        if error != nil || connection == .offline || cacheIsStale { return .orange }
        switch connection {
        case .revoked: return .red
        default: return RelayWatchStyle.foreground
        }
    }
}

/// Temporary adapter while destination views move to native navigation routes.
/// Task 5 removes this once the remaining call sites are gone.
struct RelayBackButton: View {
    @ObservedObject var model: RelayWatchModel
    var destination: RelayWatchScreen = .inbox

    var body: some View {
        Button("Back") { model.show(destination) }
    }
}
