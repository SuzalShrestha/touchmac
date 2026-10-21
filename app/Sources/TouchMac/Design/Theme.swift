import AppKit
import SwiftUI

/// Design tokens. The chrome is monochrome ink; colour belongs to the six zones,
/// and each zone keeps one hue everywhere: the 3D desk, its key, calibration and the log.
extension Color {
    static let canvas = dynamic(light: 0xE6E9EC, dark: 0x1D1F22)
    static let surface = dynamic(light: 0xF8F9FA, dark: 0x282B2F)
    static let ink = dynamic(light: 0x1B2127, dark: 0xEDEFF1)
    static let hairline = dynamic(light: 0x1B2127, dark: 0xEDEFF1).opacity(0.1)
    /// Threshold line, errors: the red needle of a seismograph.
    static let needle = dynamic(light: 0xD23F2F, dark: 0xF2654F)
    static let live = dynamic(light: 0x1E9E62, dark: 0x3DD68C)

    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
            })
    }

    static func zone(_ id: String) -> Color { Color(nsColor: NSColor(hex: ZoneHue.hex(id))) }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

enum ZoneHue {
    /// Spread around the wheel so neighbours on the desk never look alike.
    static func hex(_ id: String) -> UInt32 {
        switch id {
        case "L2": return 0x5B7CF0  // blue
        case "L1": return 0x9C6FE4  // violet
        case "R2": return 0xE5608A  // rose
        case "R1": return 0xEF8B3C  // orange
        case "F1": return 0xD3AE2E  // gold
        case "F2": return 0x2FB2C9  // cyan
        default: return 0x8A8F96
        }
    }
}

/// Zone ids in desk reading order: left column far→near, front left→right, right column near→far.
let deskOrder = ["L2", "L1", "F1", "F2", "R1", "R2"]
/// The order calibration walks through the zones.
let calibrationOrder = ["L2", "L1", "R2", "R1", "F1", "F2"]

extension Font {
    /// SF Pro Expanded: the display voice, wide like engraved hardware labels.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }
}

/// Header used at the top of every page: an expanded title and one line of help.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.display(24)).foregroundStyle(Color.ink)
                // no vertical fixedSize: the split view measures its minimum height at a tiny
                // width, where wrapped text would claim hundreds of points and push the page off
                Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Primary buttons are ink on paper, not the system accent.
struct InkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.canvas : Color.ink)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(Color.ink) : AnyShapeStyle(Color.ink.opacity(0.07)))
            )
            .overlay(Capsule().strokeBorder(Color.ink.opacity(prominent ? 0 : 0.12)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var ink: InkButtonStyle { InkButtonStyle() }
    static var inkQuiet: InkButtonStyle { InkButtonStyle(prominent: false) }
}

func qualityColor(_ value: Double) -> Color {
    value >= 0.9 ? .live : value >= 0.7 ? .orange : .needle
}
