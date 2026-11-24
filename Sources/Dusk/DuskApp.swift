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
    @StateObject private var settingsF = Flag()
    @StateObject private var mainH = Measured()
    private var settings: Bool { settingsF.on }

    private var tint: Color { Color.warm(c.kelvin) }
    private var presetName: String {
        Preset.all.first { abs($0.kelvin - c.kelvin) < 1 }?.name ?? "Custom"
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            ZStack(alignment: .top) {
                if settings {
                    settingsPage
                        .transition(.asymmetric(insertion: .offset(x: 40).combined(with: .opacity),
                                                removal: .offset(x: 40).combined(with: .opacity)))
                } else {
                    mainPage
                        .background(GeometryReader { g in
                            Color.clear.onAppear { mainH.height = g.size.height }
                                .onChange(of: g.size.height) { _, h in mainH.height = h }
                        })
                        .transition(.asymmetric(insertion: .offset(x: -40).combined(with: .opacity),
                                                removal: .offset(x: -40).combined(with: .opacity)))
                }
            }
            .frame(height: mainH.height > 0 ? mainH.height : nil, alignment: .top)
            footer
        }
        .padding(16)
        .frame(width: 320, alignment: .top)
        .font(.geist(13))
        .background {
            ZStack(alignment: .top) {
                LinearGradient(colors: [tint.opacity(c.enabled ? 0.26 : 0.04), .clear], startPoint: .top, endPoint: .center)
                DustLayer(tint: tint).opacity(c.enabled ? 1 : 0.35)
                Image(nsImage: Grain.image).resizable(resizingMode: .tile)
                    .opacity(0.045).blendMode(.overlay)
            }
            .allowsHitTesting(false)
        }
        .background(RoundedWindow(radius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1).allowsHitTesting(false))
        .animation(spring, value: c.enabled)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: settings)
        .animation(spring, value: c.scheduleOn)
        .animation(spring, value: c.gammaOK)
        .onChange(of: c.startHour) { haptic() }
        .onChange(of: c.endHour) { haptic() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: MenuIcon.make(on: true, size: 20))
                .renderingMode(.template)
                .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.54), Color(red: 1, green: 0.6, blue: 0.3), Color(red: 0.95, green: 0.31, blue: 0.48)],
                                                startPoint: .top, endPoint: .bottom))
            Text(settings ? "Settings" : "Dusk").font(.serif(22))
                .contentTransition(.opacity)
            Spacer()
            Button { settingsF.on.toggle() } label: {
                Image(systemName: settings ? "xmark" : "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 28)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
            }
            .buttonStyle(PressStyle())
            .foregroundStyle(.secondary)
            .help(settings ? "Back" : "Settings")
            .accessibilityLabel(settings ? "Close settings" : "Open settings")
            GlowSwitch(isOn: $c.enabled, tint: tint, name: "Dusk", onIcon: "sun.max.fill", offIcon: "moon.fill")
        }
    }

    private var mainPage: some View {
        VStack(spacing: 14) {
            WarmthDial(kelvin: $c.kelvin, enabled: $c.enabled, presetName: presetName)
                .help("Drag the ring to set warmth. Click the center to turn Dusk on or off.")
            VStack(alignment: .leading, spacing: 12) {
                label("Brightness", icon: "sun.min.fill")
                BrightnessBars(value: $c.brightness, tint: tint)
                FlowLayout(spacing: 6) {
                    ForEach(Preset.all) { p in
                        Chip(preset: p, selected: abs(p.kelvin - c.kelvin) < 1, ns: ns) {
                            withAnimation(spring) { c.kelvin = p.kelvin }
                        }
                    }
                }
            }
            .glassCard()
            .disabled(!c.enabled).opacity(c.enabled ? 1 : 0.5)
        }
    }

    private var settingsPage: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                ToggleRow(icon: "waveform.path.ecg", title: "Flicker-free", sub: "Backlight at 100%, dim in software", on: $c.flickerFree, tint: .mint)
                ToggleRow(icon: "square.grid.3x3.fill", title: "No dithering", sub: "Turns off temporal dithering", on: $c.antiDither, tint: .cyan)
                if !c.gammaOK {
                    Label("macOS ignored the color change, so the backlight was left alone.", systemImage: "exclamationmark.triangle.fill")
                        .font(.geist(11)).foregroundStyle(.orange)
                        .transition(.opacity)
                }
            }
            .glassCard()
            VStack(spacing: 12) {
                ToggleRow(icon: "clock.fill", title: "Schedule", sub: "Warm up automatically at night", on: $c.scheduleOn, tint: .orange)
                if c.scheduleOn {
                    HStack(spacing: 8) {
                        Picker("", selection: $c.startHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $c.endHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .transition(.opacity)
                }
            }
            .glassCard()
            VStack(spacing: 12) {
                ToggleRow(icon: "power", title: "Launch at login", sub: "Start Dusk when you log in", on: $c.launchAtLogin, tint: .ember)
                ToggleRow(icon: "speaker.wave.2.fill", title: "Sounds", sub: "Soft clicks on every control", on: $c.sounds, tint: .pink)
            }
            .glassCard()
        }
    }

    private var credit: some View {
        Link(destination: URL(string: "https://justaziz.com?utm_source=dusk-app")!) {
            HStack(spacing: 4) {
                Text("Built with")
                Image(systemName: "heart.fill").foregroundStyle(Color.ember)
                Text("by Aziz").underline()
            }
            .font(.geist(10.5))
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("justaziz.com")
    }

    private var footer: some View {
        HStack {
            credit
            Spacer()
            Button("Quit") { haptic(.generic); c.shutdown(); NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.geist(11, .medium)).foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
    }

    private func label(_ t: String, icon: String) -> some View {
        Label(t, systemImage: icon).font(.geist(12, .semibold)).foregroundStyle(.secondary)
    }
}
