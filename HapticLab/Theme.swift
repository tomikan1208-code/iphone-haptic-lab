import SwiftUI

enum LabTheme {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.075)
    static let panel = Color(red: 0.075, green: 0.094, blue: 0.137)
    static let elevated = Color(red: 0.106, green: 0.129, blue: 0.180)
    static let mint = Color(red: 0.49, green: 0.94, blue: 0.80)
    static let violet = Color(red: 0.72, green: 0.65, blue: 1)
    static let coral = Color(red: 1, green: 0.54, blue: 0.51)
    static let muted = Color(red: 0.58, green: 0.64, blue: 0.73)

    static func accent(for category: String) -> Color {
        switch category {
        case "rhythm": return violet
        case "texture": return Color(red: 0.50, green: 0.73, blue: 1)
        default: return mint
        }
    }
}

struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(LabTheme.panel, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.055), lineWidth: 1)
            }
    }
}

extension View {
    func labPanel() -> some View { modifier(PanelModifier()) }
}

struct SectionIntro: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(LabTheme.mint)
            Text(title)
                .font(.system(size: 27, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(LabTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol = "play.fill"
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .foregroundStyle(LabTheme.background)
                .background(LabTheme.mint, in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain)
    }
}

struct ParameterSlider: View {
    let title: String
    let valueLabel: String
    let leading: String
    let trailing: String
    let identifier: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.01

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(valueLabel)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LabTheme.mint)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .tint(LabTheme.mint)
                .accessibilityLabel(title)
                .accessibilityValue(valueLabel)
                .accessibilityIdentifier(identifier)
            HStack {
                Text(leading)
                Spacer()
                Text(trailing)
            }
            .font(.system(size: 11))
            .foregroundStyle(LabTheme.muted)
        }
    }
}

struct TactileWave: View {
    var intensity = 0.6
    var sharpness = 0.5
    var color = LabTheme.mint
    var phase: Double = 0

    var body: some View {
        Canvas { context, size in
            let middle = size.height / 2
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: middle))
            baseline.addLine(to: CGPoint(x: size.width, y: middle))
            context.stroke(baseline, with: .color(color.opacity(0.13)), lineWidth: 1)
            var wave = Path()
            let amplitude = size.height * 0.38 * intensity
            let cycles = 3 + sharpness * 8
            for index in 0...180 {
                let progress = Double(index) / 180
                let envelope = pow(sin(progress * .pi), 0.6)
                let y = middle - sin(progress * .pi * 2 * cycles + phase) * amplitude * envelope
                let point = CGPoint(x: size.width * progress, y: y)
                if index == 0 { wave.move(to: point) } else { wave.addLine(to: point) }
            }
            context.stroke(wave, with: .color(color.opacity(0.10)), lineWidth: 8)
            context.stroke(wave, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}

