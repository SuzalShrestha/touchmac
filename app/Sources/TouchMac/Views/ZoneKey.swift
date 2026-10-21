import SwiftUI
import TouchMacCore

/// One zone as a physical key: "the desk becomes buttons". A tap on the desk presses it
/// down and lights its LED in the zone's hue; a click opens the zone editor.
struct ZoneKey: View {
    @Environment(AppState.self) private var state
    let zoneID: String
    let highlighted: Bool
    let edit: () -> Void
    var onHover: (Bool) -> Void = { _ in }

    private var zone: ZoneConfig { state.zone(zoneID) }

    var body: some View {
        Button(action: edit) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Capsule().fill(Color.zone(zoneID)).frame(width: 16, height: 4)
                        .shadow(color: Color.zone(zoneID).opacity(lit ? 0.9 : 0), radius: 5)
                    Spacer(minLength: 4)
                    badge
                }
                Spacer(minLength: 8)
                icon.frame(height: 22)
                Spacer(minLength: 6)
                Text(zone.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text(zone.action.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(zone.doubleAction == .none ? " " : "Double: \(zone.doubleAction.label)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(KeycapStyle(hue: Color.zone(zoneID), lit: lit, raised: highlighted))
        .onHover(perform: onHover)
        .help("Edit \(zone.name)")
        .accessibilityLabel("\(zone.name), \(zone.action.label), \(statusText)")
    }

    private var lit: Bool { state.flashZone == zoneID }

    @ViewBuilder
    private var icon: some View {
        if case .openApp(let path) = zone.action {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: zone.action.symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(zone.action == .none ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.ink))
        }
    }

    @ViewBuilder
    private var badge: some View {
        if let p = [zone.action, zone.doubleAction].compactMap(\.requiredPermission).first(where: { !$0.granted }) {
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(Color.needle)
                .help("\(p.title): \(p.purpose) Grant it in Settings.")
        } else if !zone.isCalibrated {
            Text("Calibrate")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
        } else if let score = state.quality?.perZone[zoneID] {
            Text("\(Int((score * 100).rounded()))%")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(qualityColor(score))
                .help(state.quality?.confusedWith[zoneID].map { "Sometimes read as \(state.zone($0).name)" } ?? "Calibrated")
        } else {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.live)
        }
    }

    private var statusText: String {
        guard zone.isCalibrated else { return "not calibrated" }
        return state.quality?.perZone[zoneID].map { "\(Int($0 * 100)) percent accurate" } ?? "calibrated"
    }
}

/// A 2.5D keycap: a top face on a skirt. Pressing (or a desk tap) sinks the top face.
struct KeycapStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    let hue: Color
    var lit = false
    var raised = false

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || lit
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        let top = RoundedRectangle(cornerRadius: 12, style: .continuous)

        return configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                top.fill(
                    LinearGradient(
                        colors: dark
                            ? [Color(white: 0.25), Color(white: 0.205)]
                            : [Color(white: 1), Color(white: 0.945)],
                        startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                top.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(dark ? 0.12 : 1), .clear],
                        startPoint: .top, endPoint: .center), lineWidth: 1)
            )
            .overlay(top.fill(hue.opacity(lit ? (dark ? 0.16 : 0.1) : 0)).allowsHitTesting(false))
            .padding(.horizontal, 4)
            .padding(.top, down ? 6 : (raised ? 2 : 3))
            .padding(.bottom, down ? 3 : (raised ? 10 : 9))
            .background(
                shape.fill(
                    LinearGradient(
                        colors: dark
                            ? [Color(white: 0.13), Color(white: 0.09)]
                            : [Color(white: 0.84), Color(white: 0.76)],
                        startPoint: .top, endPoint: .bottom))
            )
            .overlay(shape.strokeBorder(lit ? hue.opacity(0.9) : Color.black.opacity(dark ? 0.5 : 0.08), lineWidth: lit ? 1.5 : 1))
            .shadow(
                color: lit ? hue.opacity(0.55) : .black.opacity(dark ? 0.45 : 0.16),
                radius: lit ? 16 : (raised ? 8 : 4), y: lit ? 0 : (raised ? 5 : 3)
            )
            .contentShape(shape)
            .animation(.spring(response: 0.16, dampingFraction: 0.5), value: down)
            .animation(.easeOut(duration: 0.15), value: raised)
    }
}
