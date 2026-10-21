import SwiftUI

/// The rendered desk with live overlays: a glow where the pointer is, ripples where a tap
/// lands, the zone names, and during calibration a dolly in on one zone with a ring of ten dots.
struct DeskStage: View {
    @Environment(AppState.self) private var state
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A zone to light up, for example the key under the pointer.
    var highlighted: String?
    /// Calibration: the camera moves in on this zone and shows its tap count.
    var focus: String?
    var showsLabels = true
    var onSelect: ((String) -> Void)?
    var onHover: ((String?) -> Void)?

    @State private var render: DeskRender.Output?
    @State private var hovered: String?
    @State private var ripples: [String: Int] = [:]

    private let zoom: CGFloat = 2.1

    /// The cache is warm after the first load, so later pages show the desk at once.
    private var current: DeskRender.Output? { DeskRender.cached(dark: scheme == .dark) ?? render }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                if let r = current {
                    Image(nsImage: r.nsImage)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .transition(.opacity)
                    ForEach(deskOrder, id: \.self) { id in
                        spot(id, r, size)
                    }
                } else {
                    Rectangle().fill(Color.ink.opacity(0.06))
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(focus == nil ? 1 : zoom)
            .offset(dolly(size))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard onSelect != nil else { return }
                if case .active(let p) = phase { setHover(nearest(p, size)) } else { setHover(nil) }
            }
            .onTapGesture { p in
                if let id = nearest(p, size) { onSelect?(id) }
            }
        }
        .aspectRatio(DeskRender.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.hairline))
        .animation(reduceMotion ? nil : .smooth(duration: 0.9), value: focus)
        .animation(.easeOut(duration: 0.35), value: current == nil)
        .task(id: scheme) { render = await DeskRender.output(dark: scheme == .dark) }
        .onChange(of: state.flashZone) { _, id in
            if let id { ripples[id, default: 0] += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your MacBook on the desk, with six tap zones around it")
    }

    // MARK: overlays

    @ViewBuilder
    private func spot(_ id: String, _ r: DeskRender.Output, _ size: CGSize) -> some View {
        let hue = Color.zone(id)
        let ring = polygon(r.rings[id] ?? [], size)
        let c = r.centers[id] ?? .zero
        let center = UnitPoint(x: c.x, y: c.y)
        let lit = state.flashZone == id || hovered == id || highlighted == id || focus == id

        ring.fill(
            RadialGradient(
                colors: [hue, hue.opacity(0)], center: center, startRadius: 0,
                endRadius: (size.width * 0.06))
        )
        .scaleEffect(1.5, anchor: center)
        .blur(radius: 10)
        .opacity(lit ? (state.flashZone == id ? 0.9 : 0.55) : 0)
        .blendMode(scheme == .dark ? .plusLighter : .normal)
        .animation(.easeOut(duration: state.flashZone == id ? 0.08 : 0.35), value: lit)
        .allowsHitTesting(false)

        if !reduceMotion {
            KeyframeAnimator(initialValue: 0.0, trigger: ripples[id] ?? 0) { t in
                ZStack {
                    ripple(ring, hue, t, center)
                    ripple(ring, hue, t - 0.22, center)
                }
            } keyframes: { _ in
                MoveKeyframe(0.001)
                LinearKeyframe(1.0, duration: 1.1, timingCurve: .easeOut)
                MoveKeyframe(0)
            }
            .allowsHitTesting(false)
        }

        if focus == id, let dots = r.dots[id] {
            ForEach(dots.indices, id: \.self) { i in
                let filled = i < state.calibrationTaps
                Circle()
                    .fill(filled ? hue : Color.white.opacity(0.28))
                    .overlay(Circle().strokeBorder(.white.opacity(filled ? 0.8 : 0.5), lineWidth: 0.75))
                    .frame(width: 5.5, height: 5.5)
                    .shadow(color: filled ? hue : .clear, radius: 3)
                    .scaleEffect(filled ? 1.15 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: filled)
                    .position(x: dots[i].x * size.width, y: dots[i].y * size.height)
            }
        }

        if showsLabels && focus == nil {
            let top = (r.rings[id] ?? []).map(\.y).min() ?? c.y
            ZoneTag(name: state.zone(id).name, hue: hue, lit: lit)
                .position(x: c.x * size.width, y: top * size.height - 16)
                .allowsHitTesting(false)
        }
    }

    private func ripple(_ ring: Path, _ hue: Color, _ t: Double, _ center: UnitPoint) -> some View {
        let visible = t > 0 && t < 1
        return
            ring
            .stroke(hue, lineWidth: 2.4)
            .scaleEffect(0.5 + max(t, 0) * 2.6, anchor: center)
            .opacity(visible ? (1 - t) * 0.9 : 0)
    }

    private func polygon(_ points: [CGPoint], _ size: CGSize) -> Path {
        Path { p in
            p.addLines(points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) })
            p.closeSubpath()
        }
    }

    /// Moves the zoomed picture so the focused zone sits in the middle, without showing its edges.
    private func dolly(_ size: CGSize) -> CGSize {
        guard let id = focus, let c = current?.centers[id] else { return .zero }
        let limitX = (zoom - 1) * size.width / 2, limitY = (zoom - 1) * size.height / 2
        let x = (0.5 - c.x) * size.width * zoom, y = (0.5 - c.y) * size.height * zoom
        return CGSize(width: min(max(x, -limitX), limitX), height: min(max(y, -limitY), limitY))
    }

    private func nearest(_ p: CGPoint, _ size: CGSize) -> String? {
        guard let r = current else { return nil }
        let reach = size.width * 0.075
        return r.centers
            .map { (id: $0.key, d: hypot($0.value.x * size.width - p.x, $0.value.y * size.height - p.y)) }
            .filter { $0.d < reach }
            .min { $0.d < $1.d }?.id
    }

    private func setHover(_ id: String?) {
        guard id != hovered else { return }
        hovered = id
        onHover?(id)
        if id != nil { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
    }
}

/// The small name plate that floats above each spot.
private struct ZoneTag: View {
    let name: String
    let hue: Color
    let lit: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(hue).frame(width: 6, height: 6)
            Text(name).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(lit ? hue.opacity(0.9) : Color.white.opacity(0.25), lineWidth: lit ? 1.2 : 0.5))
        .scaleEffect(lit ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: lit)
        .fixedSize()
    }
}
