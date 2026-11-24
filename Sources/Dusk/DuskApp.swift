import SwiftUI

@main
struct DuskApp: App {
    init() { Fonts.register() }
    @StateObject private var c = Controller()

    var body: some Scene {
        MenuBarExtra {
            ContentView(c: c)
        } label: {
            Image(nsImage: MenuIcon.make(on: c.enabled))
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var c: Controller
    @Namespace private var ns
    @StateObject private var moreF = Flag()
    private var more: Bool { moreF.on }

    private var tint: Color { Color.warm(c.kelvin) }
    private var presetName: String {
        Preset.all.first { abs($0.kelvin - c.kelvin) < 1 }?.name ?? "Custom"
    }

    var body: some View {
        VStack(spacing: 16) {
            header
            hero
            brightness
            presets
            Divider().opacity(0.4)
            advanced
            footer
        }
        .padding(18)
        .frame(width: 320)
        .font(.geist(13))
        .background(alignment: .top) {
            LinearGradient(colors: [tint.opacity(c.enabled ? 0.24 : 0.04), .clear], startPoint: .top, endPoint: .center)
                .allowsHitTesting(false)
        }
        .animation(spring, value: c.enabled)
        .animation(spring, value: more)
        .animation(spring, value: c.scheduleOn)
        .animation(spring, value: c.gammaOK)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuIcon.make(on: true, size: 20))
                .renderingMode(.template)
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.54), Color(red: 1, green: 0.6, blue: 0.3), Color(red: 0.95, green: 0.31, blue: 0.48)],
                                                startPoint: .top, endPoint: .bottom))
            Text("Dusk").font(.serif(22))
            Spacer()
            GlowSwitch(isOn: $c.enabled, tint: tint, name: "Dusk", onIcon: "sun.max.fill", offIcon: "moon.fill")
        }
    }

    private var hero: some View {
        WarmthDial(kelvin: $c.kelvin, enabled: $c.enabled, presetName: presetName)
            .padding(.vertical, 4)
            .help("Drag the ring to set warmth. Click the center to turn Dusk on or off.")
    }

    private var brightness: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                label("Brightness", icon: "sun.min.fill")
                Spacer()
                Text("\(Int(c.brightness * 100))%").font(.geist(12, .medium))
                    .foregroundStyle(.secondary).contentTransition(.numericText(value: c.brightness))
            }
            GlowSlider(value: $c.brightness, range: 0.05...1, colors: [tint.opacity(0.55), tint], tint: tint, fill: true,
                       snaps: [0.25, 0.5, 0.75, 1], name: "Brightness",
                       label: { "\(Int($0 * 100))%" },
                       icon: { $0 < 0.4 ? "sun.min.fill" : "sun.max.fill" })
        }
        .disabled(!c.enabled).opacity(c.enabled ? 1 : 0.45)
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Preset.all) { p in
                    Chip(preset: p, selected: abs(p.kelvin - c.kelvin) < 1, ns: ns) {
                        withAnimation(spring) { c.kelvin = p.kelvin }
                    }
                }
            }
            .padding(.horizontal, 1).padding(.vertical, 2)
        }
        .disabled(!c.enabled).opacity(c.enabled ? 1 : 0.45)
    }

    private var advanced: some View {
        VStack(spacing: 10) {
            Button { moreF.on.toggle() } label: {
                HStack {
                    Text("Display health").font(.geist(12, .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.geist(10, .bold)).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(more ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if more {
                VStack(spacing: 12) {
                    ToggleRow(icon: "waveform.path.ecg", title: "Flicker-free", sub: "Backlight at 100%, dim in software", on: $c.flickerFree, tint: .mint)
                    ToggleRow(icon: "square.grid.3x3.fill", title: "No dithering", sub: "Turns off temporal dithering", on: $c.antiDither, tint: .cyan)
                    ToggleRow(icon: "clock.fill", title: "Schedule", sub: "Warm up automatically at night", on: $c.scheduleOn, tint: .orange)
                    if c.scheduleOn {
                        HStack(spacing: 8) {
                            Picker("", selection: $c.startHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            Picker("", selection: $c.endHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                        }
                        .labelsHidden().pickerStyle(.menu)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if !c.gammaOK {
                        Label("macOS ignored gamma. Backlight pin skipped.", systemImage: "exclamationmark.triangle.fill")
                            .font(.geist(11)).foregroundStyle(.orange)
                            .transition(.opacity)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Launch at login", isOn: $c.launchAtLogin).toggleStyle(.checkbox).font(.geist(11))
            Spacer()
            Button("Quit") { c.shutdown(); NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.geist(11, .medium)).foregroundStyle(.secondary)
        }
    }

    private func label(_ t: String, icon: String) -> some View {
        Label(t, systemImage: icon).font(.geist(12, .semibold)).foregroundStyle(.secondary)
    }
}
