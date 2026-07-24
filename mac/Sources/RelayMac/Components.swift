import SwiftUI
import RelayCore

enum RelayPalette {
    static let accent = Color(red: 0.25, green: 0.92, blue: 0.76)
    static let amber = Color(red: 1.0, green: 0.70, blue: 0.24)
    static let danger = Color(red: 1.0, green: 0.34, blue: 0.38)
    static let panel = Color.white.opacity(0.065)
}

struct DashboardHeader: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(eyebrow.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(RelayPalette.accent)
            Text(title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.callout)
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
            .background(RelayPalette.panel, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
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
            .foregroundStyle(ready ? RelayPalette.accent : RelayPalette.amber)
            .background(
                (ready ? RelayPalette.accent : RelayPalette.amber).opacity(0.12),
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
                .foregroundStyle(status.isReady ? RelayPalette.accent : .secondary)
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
