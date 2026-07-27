import SwiftUI
import RelayCore

enum RelayPalette {
    static let accent = Color.accentColor
    static let amber = Color.orange
    static let danger = Color.red
    static let panel = Material.thin
}

struct DashboardHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 620, alignment: .leading)
        }
    }
}

struct RelayPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RelayPalette.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.08))
            }
    }
}

struct StatusPill: View {
    let text: String
    let ready: Bool

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(ready ? .primary : RelayPalette.amber)
            .background(
                (ready ? Color.primary : RelayPalette.amber).opacity(0.12),
                in: Capsule()
            )
    }
}

struct RequirementRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: SetupRequirementStatus

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .frame(width: 28, height: 28)
                .foregroundStyle(status.isReady ? .primary : .secondary)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusPill(text: status.isReady ? "Ready" : "Needs setup", ready: status.isReady)
        }
        .accessibilityElement(children: .combine)
    }
}

struct EmptyPanel: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        RelayPanel {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(RelayPalette.accent)
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
        }
    }
}
