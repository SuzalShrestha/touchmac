import SwiftUI
import TouchMacCore

struct ZonePadView: View {
    @Environment(AppState.self) private var state
    let zoneID: String
    let edit: () -> Void
    @State private var hovering = false

    private var zone: ZoneConfig { state.zone(zoneID) }
    private var isFlashing: Bool { state.flashZone == zoneID }

    var body: some View {
        Button(action: edit) {
            VStack(spacing: 6) {
                icon
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isFlashing ? .white : Color.accentColor)
                    .frame(height: 28)
                Text(zone.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(zone.action.label)
                    .font(.caption)
                    .foregroundStyle(isFlashing ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
                if zone.doubleAction != .none {
                    Text("2× \(zone.doubleAction.label)")
                        .font(.caption2)
                        .foregroundStyle(isFlashing ? .white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                badge
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .frame(width: 150, height: 126)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFlashing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.background.secondary))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isFlashing ? Color.accentColor
                                  : hovering ? Color.accentColor.opacity(0.6)
                                  : Color.primary.opacity(0.1),
                                  lineWidth: isFlashing ? 2 : 1)
            )
            .shadow(color: isFlashing ? Color.accentColor.opacity(0.55) : .black.opacity(hovering ? 0.16 : 0.06),
                    radius: isFlashing ? 16 : 8, y: 3)
            .scaleEffect(isFlashing ? 1.05 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isFlashing)
            .animation(.easeOut(duration: 0.15), value: hovering)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Edit \(zone.name)")
        .accessibilityLabel("\(zone.name) zone, \(zone.action.label), \(statusText)")
    }

    @ViewBuilder
    private var badge: some View {
        if let p = [zone.action, zone.doubleAction].compactMap(\.requiredPermission).first(where: { !$0.granted }) {
            Label("Needs permission", systemImage: "lock")
                .font(.caption2.weight(.medium))
                .foregroundStyle(isFlashing ? .white : .red)
                .help("\(p.title): \(p.purpose) Grant it in Settings.")
        } else if !zone.isCalibrated {
            Label("Calibrate", systemImage: "scope")
                .font(.caption2.weight(.medium))
                .foregroundStyle(isFlashing ? .white : .orange)
        } else if let score = state.quality?.perZone[zoneID] {
            Label("\(Int((score * 100).rounded()))%", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(isFlashing ? .white : qualityColor(score))
                .help(state.quality?.confusedWith[zoneID].map { "Sometimes read as \(state.zone($0).name)" } ?? "Calibrated")
        } else {
            Label("Calibrated", systemImage: "checkmark.seal.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(isFlashing ? .white : .green)
        }
    }

    private var statusText: String {
        guard zone.isCalibrated else { return "not calibrated" }
        return state.quality?.perZone[zoneID].map { "\(Int($0 * 100)) percent accurate" } ?? "calibrated"
    }

    @ViewBuilder
    private var icon: some View {
        if case .openApp(let path) = zone.action {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 28, height: 28)
        } else {
            Image(systemName: zone.action.symbol)
        }
    }
}
