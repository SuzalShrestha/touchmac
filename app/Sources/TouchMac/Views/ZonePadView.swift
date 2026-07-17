import SwiftUI

struct ZonePadView: View {
    @EnvironmentObject var state: AppState
    let zoneID: String
    let edit: () -> Void
    @State private var hovering = false

    private var zone: ZoneConfig { state.zone(zoneID) }
    private var isFlashing: Bool { state.flashZone == zoneID }

    var body: some View {
        Button(action: edit) {
            VStack(spacing: 8) {
                icon
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(isFlashing ? .white : Color.accentColor)
                    .frame(height: 26)
                Text(zone.name)
                    .font(.callout.weight(.semibold))
                Text(zone.action.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !zone.isCalibrated {
                    Label("Calibrate", systemImage: "scope")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 14)
            .frame(width: 138, height: 110)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isFlashing ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFlashing ? Color.accentColor
                            : hovering ? Color.accentColor.opacity(0.6)
                            : Color.primary.opacity(0.1),
                            lineWidth: isFlashing ? 2 : 1)
            )
            .shadow(color: isFlashing ? Color.accentColor.opacity(0.6) : .black.opacity(hovering ? 0.18 : 0.08),
                    radius: isFlashing ? 16 : 8, y: 3)
            .scaleEffect(isFlashing ? 1.05 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isFlashing)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .accessibilityLabel("\(zone.name) zone, action: \(zone.action.label)")
    }

    @ViewBuilder
    private var icon: some View {
        if case .openApp(let path) = zone.action {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 26, height: 26)
        } else {
            Image(systemName: zone.action.symbol)
        }
    }
}
