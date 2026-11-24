import SwiftUI

final class Flag: ObservableObject { @Published var on = false }

extension Color {
    static func warm(_ kelvin: Double) -> Color {
        let c = Display.rgb(kelvin: kelvin)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
    static let ember = Color(red: 1, green: 0.604, blue: 0.302)
    static let brandGradient = LinearGradient(
        colors: [Color(red: 1, green: 0.878, blue: 0.541), .ember, Color(red: 0.949, green: 0.314, blue: 0.482)],
        startPoint: .top, endPoint: .bottom)
}

/// Control Center–style grouped module.
struct Module<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct Swatch: View {
    let preset: Preset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color.warm(preset.kelvin))
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 0.5))
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black.opacity(0.65))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(selected ? 1 : 0))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("\(preset.name) · \(Int(preset.kelvin))K")
        .accessibilityLabel("\(preset.name) preset, \(Int(preset.kelvin)) Kelvin")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SwitchRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                    .symbolEffect(.bounce, value: isOn)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
    }
}

struct BrandMark: View {
    var size: CGFloat = 18
    var body: some View {
        Image(nsImage: MenuIcon.make(on: true, size: size))
            .renderingMode(.template)
            .foregroundStyle(Color.brandGradient)
            .accessibilityHidden(true)
    }
}
