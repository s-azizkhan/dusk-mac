import SwiftUI

@main
struct DuskApp: App {
    @StateObject private var c = Controller()

    var body: some Scene {
        MenuBarExtra {
            ContentView(c: c).tint(.ember)
        } label: {
            Image(nsImage: MenuIcon.make(on: c.enabled))
                .accessibilityLabel("Dusk")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(c: c).tint(.ember)
        }
    }
}

struct ContentView: View {
    @ObservedObject var c: Controller

    private var preset: Preset? { Preset.all.first { abs($0.kelvin - c.kelvin) < 1 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Group {
                warmth
                brightness
            }
            .disabled(!c.enabled)
            .opacity(c.enabled ? 1 : 0.5)
            health
            footer
        }
        .padding(12)
        .frame(width: 300)
        .animation(.smooth(duration: 0.3), value: c.enabled)
        .animation(.smooth(duration: 0.3), value: c.gammaOK)
        .animation(.snappy(duration: 0.25), value: preset?.id)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(size: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text("Dusk").font(.headline)
                Text(c.enabled ? (c.scheduleOn ? "On · Scheduled" : "On") : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer()
            Toggle("Dusk", isOn: $c.enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Turn Dusk on or off")
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var warmth: some View {
        Module {
            HStack(alignment: .firstTextBaseline) {
                Text("Warmth").font(.subheadline.weight(.semibold))
                if let preset {
                    Text(preset.name).font(.subheadline).foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Spacer()
                Text("\(Int(c.kelvin))K")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: c.kelvin))
            }
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundStyle(.orange).accessibilityHidden(true)
                Slider(value: $c.kelvin, in: 500...6500).labelsHidden().accessibilityLabel("Warmth")
                Image(systemName: "sun.max").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            HStack(spacing: 0) {
                ForEach(Preset.all) { p in
                    Swatch(preset: p, selected: preset?.id == p.id) {
                        withAnimation(.smooth(duration: 0.45)) { c.kelvin = p.kelvin }
                    }
                    if p.id != Preset.all.last?.id { Spacer(minLength: 0) }
                }
            }
        }
    }

    private var brightness: some View {
        Module {
            HStack {
                Text("Brightness").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(c.brightness * 100))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: c.brightness))
            }
            HStack(spacing: 8) {
                Image(systemName: "sun.min").foregroundStyle(.secondary).accessibilityHidden(true)
                Slider(value: $c.brightness, in: 0.05...1).labelsHidden().accessibilityLabel("Brightness")
                Image(systemName: "sun.max.fill").foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
    }

    private var health: some View {
        Module {
            Text("Display Health").font(.subheadline.weight(.semibold))
            SwitchRow(title: "Flicker-Free", symbol: "waveform.path", isOn: $c.flickerFree)
            SwitchRow(title: "No Dithering", symbol: "circle.grid.3x3.fill", isOn: $c.antiDither)
            if !c.gammaOK {
                Label("macOS didn't apply the color change, so the backlight was left alone.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink {
                Text("Settings…")
            }
            .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            .keyboardShortcut(",")
            Spacer()
            Button("Quit Dusk") { c.shutdown(); NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

struct SettingsView: View {
    @ObservedObject var c: Controller
    private let hours = Array(0..<24)

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $c.launchAtLogin)
            }
            Section {
                Toggle("Warm the screen on a schedule", isOn: $c.scheduleOn)
                Picker("Starts at", selection: $c.startHour) {
                    ForEach(hours, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                .disabled(!c.scheduleOn)
                Picker("Ends at", selection: $c.endHour) {
                    ForEach(hours, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                .disabled(!c.scheduleOn)
            } header: {
                Text("Schedule")
            } footer: {
                Text("Outside these hours the screen returns to normal colors.").foregroundStyle(.secondary)
            }
            Section {
                Toggle("Flicker-Free", isOn: $c.flickerFree)
                Toggle("No Dithering", isOn: $c.antiDither)
            } header: {
                Text("Display Health")
            } footer: {
                Text("Flicker-Free holds the built-in backlight at full power and dims in software. No Dithering turns off temporal dithering on Apple silicon.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                Link("Source code on GitHub", destination: URL(string: "https://github.com/s-azizkhan/dusk-mac")!)
                Link("Report an issue", destination: URL(string: "https://github.com/s-azizkhan/dusk-mac/issues")!)
            } header: {
                HStack(spacing: 6) { BrandMark(size: 14); Text("About Dusk") }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
