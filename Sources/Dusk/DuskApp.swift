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
                    // Settings can be taller than the main page (test results): scroll inside the same slot.
                    ScrollView(.vertical, showsIndicators: false) { settingsPage.padding(.bottom, 12) }
                        .frame(height: mainH.height > 0 ? mainH.height : nil)
                        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92), .init(color: .clear, location: 1)],
                                             startPoint: .top, endPoint: .bottom))
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
                LinearGradient(colors: [tint.opacity(c.power ? 0.26 : 0.04), .clear], startPoint: .top, endPoint: .center)
                DustLayer(tint: tint).opacity(c.power ? 1 : 0.35)
                Image(nsImage: Grain.image).resizable(resizingMode: .tile)
                    .opacity(0.045).blendMode(.overlay)
            }
            .allowsHitTesting(false)
        }
        .background(VisibilityWatcher())
        .background(Color(red: 0.11, green: 0.102, blue: 0.141).opacity(0.94))
        .background(RoundedWindow(radius: 20))
        .environment(\.colorScheme, .dark)
        .overlay {
            if let s = c.sweepStart {
                SweepView(start: s, on: c.sweepOn)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.08), lineWidth: 1).allowsHitTesting(false))
        .animation(.easeInOut(duration: SweepView.duration), value: c.power)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: settings)
        .animation(spring, value: c.scheduleOn)
        .animation(spring, value: c.gammaOK)
        .animation(spring, value: c.checks.map(\.text))
        .onChange(of: c.selected) { haptic() }
        .animation(spring, value: c.screens.count)
        .animation(spring, value: c.selected)
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
            if c.screens.count > 1 && !settings {
                screenPicker.transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
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
            GlowSwitch(isOn: $c.power, tint: tint, name: "Dusk", onIcon: "sun.max.fill", offIcon: "moon.fill")
        }
    }

    private var screenPicker: some View {
        let cur = c.screens.first { $0.key == c.selected }
        return Menu {
            Picker("Screen", selection: $c.selected) {
                Label("All screens", systemImage: "rectangle.on.rectangle").tag("all")
                ForEach(c.screens) { s in
                    Label(c.on(s.key) ? s.name : "\(s.name) · off", systemImage: s.builtin ? "laptopcomputer" : "display").tag(s.key)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: cur == nil ? "rectangle.on.rectangle" : cur!.builtin ? "laptopcomputer" : "display")
                    .font(.system(size: 10, weight: .semibold))
                Text(cur?.name ?? "All screens").lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.7)
            }
            .font(.geist(11, .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(maxWidth: 112)
            .background(Capsule().fill(.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.6))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help("Pick the screen to change")
        .accessibilityLabel("Screen to change")
    }

    private var mainPage: some View {
        VStack(spacing: 14) {
            WarmthDial(kelvin: $c.kelvin, enabled: $c.power, presetName: presetName)
                .scrollAdjust(enabled: c.power) { n in // wheel up = warmer, 100 K a notch
                    c.kelvin = min(max(c.kelvin - n * 100, 500), 6500); Sound.shared.tick(c.kelvin / 6500)
                }
                .help("Drag the ring to set warmth. Click the center to turn Dusk on or off.")
            VStack(alignment: .leading, spacing: 12) {
                label("Brightness", icon: "sun.min.fill")
                BrightnessBars(value: $c.brightness, tint: tint)
                    .scrollAdjust(enabled: c.power) { n in // wheel up = brighter, one bar a notch
                        c.brightness = min(max(c.brightness + n * 0.05, 0.05), 1); Sound.shared.tick(c.brightness)
                    }
                FlowLayout(spacing: 6) {
                    ForEach(Preset.all) { p in
                        Chip(preset: p, selected: abs(p.kelvin - c.kelvin) < 1, ns: ns) {
                            withAnimation(spring) { c.kelvin = p.kelvin }
                        }
                    }
                }
            }
            .glassCard()
            .disabled(!c.power).opacity(c.power ? 1 : 0.6)
        }
    }

    private var settingsPage: some View {
        VStack(spacing: 12) {
            VStack(spacing: 12) {
                ToggleRow(icon: "waveform.path.ecg", title: "Flicker-free", sub: c.screens.count > 1 ? (Display.builtinIsMiniLED ? "Holds external monitors at 100% (DDC)" : "Also holds external monitors at 100% (DDC)") : Display.builtinIsMiniLED ? "Can't help mini-LED (XDR) screens" : "Stops the backlight pulsing when dimmed", on: $c.flickerFree, tint: .mint)
                ToggleRow(icon: "square.grid.3x3.fill", title: "No dithering", sub: "Stops faint pixel shimmer", on: $c.antiDither, tint: .cyan)
                Button { c.runChecks(); haptic() } label: {
                    Label(c.checks.isEmpty ? "Test these" : "Test again", systemImage: "checkmark.seal")
                        .font(.geist(12, .medium)).frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(0.08)))
                }
                .buttonStyle(PressStyle())
                ForEach(c.checks) { k in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: k.state == .ok ? "checkmark.circle.fill" : k.state == .warn ? "exclamationmark.triangle.fill" : "minus.circle")
                            .foregroundStyle(k.state == .ok ? .mint : k.state == .warn ? .orange : .secondary)
                        Text(k.text).font(.geist(11)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    Group {
                        if k.id.hasPrefix("ext-") {
                            EmptyView()
                        } else if k.id == "flicker" {
                            WaveGraphic(duty: k.state == .ok ? nil : Display.builtinIsMiniLED ? 0.85 : 0.45, tint: k.state == .ok ? .mint : .orange)
                        } else {
                            DitherGraphic(shimmer: k.state != .ok)
                        }
                    }
                    .transition(.opacity)
                    Button {
                        if k.id == "flicker" || k.id.hasPrefix("ext-") { ScreenTest.open(FlickerScreenTest()) }
                        else { ScreenTest.open(DitherScreenTest(c: c), onClose: { [c] in Display.setDithering(disabled: c.antiDither) }) }
                    } label: {
                        Label("Try it on screen", systemImage: "rectangle.inset.filled")
                            .font(.geist(11, .medium)).foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PressStyle())
                }
                if c.checks.contains(where: { $0.id == "flicker" }) {
                    Text("Or film the screen in slow motion with your phone at low brightness: dark rolling bands mean flicker.")
                        .font(.geist(10.5)).foregroundStyle(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
            .foregroundStyle(.white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help("justaziz.com")
    }

    private var footer: some View {
        HStack {
            credit
            Spacer()
            Button("Quit") { haptic(.generic); c.shutdown(); NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.geist(11, .medium)).foregroundStyle(.white.opacity(0.8))
                .keyboardShortcut("q")
        }
    }

    private func label(_ t: String, icon: String) -> some View {
        Label(t, systemImage: icon).font(.geist(12, .semibold)).foregroundStyle(.white.opacity(0.85))
    }
}
