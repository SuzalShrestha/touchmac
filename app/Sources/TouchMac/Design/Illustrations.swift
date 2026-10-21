import SwiftUI

// Flat isometric illustrations, drawn in code. Each one is a stack of slabs: a flat top face
// laid onto the isometric floor, extruded by repeating its outline downwards.

extension View {
    /// Lays a flat view onto the isometric floor (rotate 45°, squash to 57.7 %).
    func isometric() -> some View {
        rotationEffect(.degrees(45)).scaleEffect(x: 1, y: 0.5774)
    }
}

struct IsoSlab<Content: View>: View {
    var width: CGFloat
    var length: CGFloat
    var height: CGFloat
    var top: Color
    var side: Color
    var radius: CGFloat = 10
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            ForEach(0..<max(Int(height), 1), id: \.self) { i in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(side)
                    .brightness(-Double(i) / Double(max(height, 1)) * 0.12)
                    .frame(width: width, height: length)
                    .isometric()
                    .offset(y: height - CGFloat(i))
            }
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(top)
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                content
            }
            .frame(width: width, height: length)
            .isometric()
        }
    }
}

extension IsoSlab where Content == EmptyView {
    init(width: CGFloat, length: CGFloat, height: CGFloat, top: Color, side: Color, radius: CGFloat = 10) {
        self.init(width: width, length: length, height: height, top: top, side: side, radius: radius) { EmptyView() }
    }
}

private enum Palette {
    static let oakTop = Color.dynamic(light: 0xD8C2A3, dark: 0x5A3D2A)
    static let oakSide = Color.dynamic(light: 0xB79A75, dark: 0x3B271B)
    static let metalTop = Color.dynamic(light: 0xE3E5E8, dark: 0x4A4D52)
    static let metalSide = Color.dynamic(light: 0xA9ADB3, dark: 0x2B2D30)
    static let boardTop = Color.dynamic(light: 0x2F4A46, dark: 0x22342F)
    static let boardSide = Color.dynamic(light: 0x1E302D, dark: 0x15201D)
    static let capTop = Color.dynamic(light: 0xFFFFFF, dark: 0x3A3E43)
    static let capSide = Color.dynamic(light: 0xC6CAD0, dark: 0x1D1F22)
}

/// The desk from above: the MacBook, six spots, and one spot rippling.
struct DeskIllustration: View {
    var rippling: String? = "R1"
    var tapDots = 0

    var body: some View {
        IsoSlab(width: 250, length: 170, height: 12, top: Palette.oakTop, side: Palette.oakSide, radius: 14) {
            ZStack {
                // grain
                VStack(spacing: 9) {
                    ForEach(0..<17, id: \.self) { i in
                        Capsule().fill(Color.black.opacity(i % 3 == 0 ? 0.06 : 0.03)).frame(height: 1.5)
                    }
                }
                .padding(10)
                RoundedRectangle(cornerRadius: 6).fill(Palette.metalSide).frame(width: 96, height: 66).offset(x: 1.5, y: 1.5)
                RoundedRectangle(cornerRadius: 6).fill(Palette.metalTop).frame(width: 96, height: 66)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.75)).frame(width: 80, height: 28).padding(.top, 8)
                    }
                ForEach(Array(spotPositions), id: \.key) { id, p in
                    ZStack {
                        if id == rippling {
                            ForEach(1..<4) { i in
                                Circle().stroke(Color.zone(id).opacity(1 - Double(i) * 0.25), lineWidth: 1.5)
                                    .frame(width: 14 + CGFloat(i) * 13)
                            }
                            ForEach(0..<10, id: \.self) { i in
                                Circle().fill(i < tapDots ? Color.zone(id) : Color.black.opacity(0.15))
                                    .frame(width: 3.5)
                                    .offset(y: -30)
                                    .rotationEffect(.degrees(Double(i) * 36))
                            }
                        }
                        Circle().fill(Color.zone(id)).frame(width: 10)
                        Circle().stroke(Color.zone(id), lineWidth: 1).frame(width: 18)
                    }
                    .offset(x: p.x, y: p.y)
                }
            }
        }
        .frame(width: 320, height: 200)
    }

    private var spotPositions: [String: CGPoint] {
        [
            "L2": CGPoint(x: -92, y: -28), "L1": CGPoint(x: -92, y: 22), "R2": CGPoint(x: 92, y: -28),
            "R1": CGPoint(x: 92, y: 22), "F1": CGPoint(x: -26, y: 60), "F2": CGPoint(x: 26, y: 60),
        ]
    }
}

/// The motion sensor on the logic board, its three axes, and the helper that reads it.
struct SensorIllustration: View {
    var body: some View {
        ZStack {
            IsoSlab(width: 210, length: 150, height: 9, top: Palette.boardTop, side: Palette.boardSide, radius: 12) {
                ZStack {
                    // traces
                    ForEach(0..<6, id: \.self) { i in
                        Capsule().fill(Color.white.opacity(0.1)).frame(width: 150, height: 2)
                            .offset(y: CGFloat(i) * 18 - 45)
                    }
                    ForEach(1..<4) { i in
                        Circle().stroke(Color.zone(calibrationOrder[i]).opacity(0.75), lineWidth: 1.5)
                            .frame(width: 70 + CGFloat(i) * 30)
                    }
                }
            }
            IsoSlab(width: 62, length: 62, height: 8, top: Color(white: 0.12), side: Color(white: 0.05), radius: 6) {
                Circle().fill(Color.white.opacity(0.7)).frame(width: 6).offset(x: -20, y: -20)
            }
            .offset(y: -9)
            axes.offset(y: -22)
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 30))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.zone("F2"))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .offset(x: 108, y: -58)
        }
        .frame(width: 320, height: 200)
    }

    private var axes: some View {
        Canvas { ctx, size in
            let o = CGPoint(x: size.width / 2, y: size.height / 2)
            let dirs: [(CGVector, String)] = [
                (CGVector(dx: 0.866, dy: 0.5), "L2"), (CGVector(dx: -0.866, dy: 0.5), "R2"),
                (CGVector(dx: 0, dy: -1), "F1"),
            ]
            for (d, id) in dirs {
                let end = CGPoint(x: o.x + d.dx * 52, y: o.y + d.dy * 52)
                var line = Path()
                line.move(to: o); line.addLine(to: end)
                ctx.stroke(line, with: .color(.zone(id)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(.zone(id)))
            }
        }
        .frame(width: 130, height: 130)
    }
}

/// Two keys: media keys (Accessibility) and screenshots (Screen Recording).
struct PermissionIllustration: View {
    var body: some View {
        ZStack {
            IsoSlab(width: 220, length: 140, height: 10, top: Palette.oakTop, side: Palette.oakSide, radius: 14)
            key("speaker.wave.2.fill", hue: Color.zone("L1")).offset(x: -46, y: -14)
            key("camera.viewfinder", hue: Color.zone("R2")).offset(x: 46, y: -14)
        }
        .frame(width: 320, height: 200)
    }

    private func key(_ symbol: String, hue: Color) -> some View {
        IsoSlab(width: 70, length: 70, height: 14, top: Palette.capTop, side: Palette.capSide, radius: 12) {
            ZStack(alignment: .topLeading) {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(hue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Capsule().fill(hue).frame(width: 14, height: 3).padding(9)
            }
            .rotationEffect(.degrees(-45))  // upright to the viewer once laid on the floor
        }
    }
}
