import SwiftUI

struct MainView: View {
    @EnvironmentObject var state: AppState
    @State private var editingZone: ZoneConfig?

    var body: some View {
        VStack(spacing: 0) {
            header
            deck
            footer
        }
        .frame(width: 760, height: 560)
        .background(background)
        .sheet(item: $editingZone) { zone in
            ZoneEditorView(zone: zone)
                .environmentObject(state)
        }
        .overlay {
            if state.calibratingZone != nil {
                CalibrationOverlay()
                    .environmentObject(state)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.calibratingZone)
    }

    private var background: some View {
        LinearGradient(colors: [Color(nsColor: .windowBackgroundColor),
                                Color(nsColor: .underPageBackgroundColor)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TouchMac")
                    .font(.title2.bold())
                Text("Your desk is the button")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
            Toggle("Test mode", isOn: $state.testMode)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Detect and flash zones without running actions")
            Toggle("Enabled", isOn: $state.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var statusPill: some View {
        if state.sensorAlive {
            Label("Sensor live", systemImage: "dot.radiowaves.left.and.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.green.opacity(0.12), in: Capsule())
        } else {
            Button {
                state.startHelper()
            } label: {
                Label(state.helperStarting ? "Starting…" : "Start Sensor",
                      systemImage: "power")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(state.helperStarting)
            .help("Launches the sensor helper (asks for admin password once per boot)")
        }
    }

    private var deck: some View {
        HStack(spacing: 18) {
            VStack(spacing: 16) {
                ZonePadView(zoneID: "L2", edit: { editingZone = state.zone("L2") })
                ZonePadView(zoneID: "L1", edit: { editingZone = state.zone("L1") })
            }
            VStack(spacing: 16) {
                MacBookView()
                HStack(spacing: 16) {
                    ZonePadView(zoneID: "F1", edit: { editingZone = state.zone("F1") })
                    ZonePadView(zoneID: "F2", edit: { editingZone = state.zone("F2") })
                }
            }
            VStack(spacing: 16) {
                ZonePadView(zoneID: "R2", edit: { editingZone = state.zone("R2") })
                ZonePadView(zoneID: "R1", edit: { editingZone = state.zone("R1") })
            }
        }
        .padding(.horizontal, 20)
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if state.events.isEmpty {
                Text(state.sensorAlive
                     ? "Tap the desk beside your MacBook — detected taps appear here."
                     : "Start the sensor, then calibrate each zone from its card.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.events.prefix(3)) { event in
                    HStack(spacing: 6) {
                        Text(event.date, format: .dateTime.hour().minute().second())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Text(event.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.3))
    }
}

/// Top-down MacBook illustration.
struct MacBookView: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.42)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    VStack(spacing: 8) {
                        // keyboard
                        VStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { _ in
                                HStack(spacing: 3) {
                                    ForEach(0..<13, id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.black.opacity(0.55))
                                            .frame(height: 10)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        // trackpad
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.28))
                            .frame(width: 92, height: 58)
                    }
                    .padding(.vertical, 16)
                }
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.15), lineWidth: 1))
                .frame(width: 300, height: 200)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        }
        .accessibilityLabel("MacBook, seen from above")
    }
}
