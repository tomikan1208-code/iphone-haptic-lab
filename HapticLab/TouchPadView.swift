import SwiftUI

struct TouchPadView: View {
    @State private var intensity = 0.5
    @State private var sharpness = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionIntro(eyebrow: "EXPLORE BY TOUCH", title: "指先で、感触を探す。",
                         detail: "パッドに触れたまま動かしてみよう。\n上下で強さ、左右で鋭さが変わります。")

            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    readout("強さ", value: intensity)
                    readout("鋭さ", value: sharpness)
                }
                TouchSurface(intensity: $intensity, sharpness: $sharpness).frame(height: 225)
                HStack {
                    Text("やわらかい")
                    Spacer()
                    Text("くっきり")
                }
                .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                Text("指を離すと止まります。1回の振動は最大20秒。")
                    .font(.system(size: 10)).foregroundStyle(LabTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .labPanel()

            Text("まずは左下から右上へ。\n柔らかい振動が、くっきりした感触へ変わります。")
                .font(.system(size: 12)).foregroundStyle(LabTheme.muted).lineSpacing(5)
                .padding(.horizontal, 3)
        }
    }

    private func readout(_ title: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(LabTheme.muted)
            Spacer(minLength: 0)
            Text("\(Int(value * 100))%")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(LabTheme.mint).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(LabTheme.elevated, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct TouchSurface: View {
    @EnvironmentObject private var haptics: HapticController
    @Environment(\.scenePhase) private var scenePhase
    @Binding var intensity: Double
    @Binding var sharpness: Double
    @State private var isTouching = false
    @State private var gestureSessionStarted = false

    var body: some View {
        GeometryReader { geometry in
            surfaceBackground
                .overlay {
                    touchIndicator.position(
                        x: 14 + CGFloat(sharpness) * (geometry.size.width - 28),
                        y: 14 + CGFloat(1 - intensity) * (geometry.size.height - 28)
                    )
                }
                .contentShape(RoundedRectangle(cornerRadius: 22))
                .gesture(touchGesture(in: geometry.size))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("触感パッド。上下で強さ、左右で鋭さを調整")
                .accessibilityIdentifier("touch.pad")
        }
        .onDisappear {
            gestureSessionStarted = false
            isTouching = false
            haptics.endPad()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { gestureSessionStarted = false; isTouching = false }
        }
        .onChange(of: haptics.isPadPlaying) { playing in
            if !playing { isTouching = false }
        }
    }

    private var surfaceBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [LabTheme.violet.opacity(0.23), LabTheme.mint.opacity(0.06)],
                                     startPoint: .topTrailing, endPoint: .bottomLeading))
            PadDots().clipShape(RoundedRectangle(cornerRadius: 22))
            if !isTouching {
                VStack(spacing: 9) {
                    Image(systemName: "hand.point.up.left").font(.system(size: 29))
                    Text("触れて、動かす").font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.55))
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.08), lineWidth: 1) }
    }

    private var touchIndicator: some View {
        Circle()
            .fill(LabTheme.mint.opacity(isTouching ? 0.16 : 0.05))
            .frame(width: isTouching ? 70 : 40, height: isTouching ? 70 : 40)
            .overlay { Circle().strokeBorder(LabTheme.mint.opacity(isTouching ? 0.8 : 0.25), lineWidth: 1) }
            .overlay { Circle().fill(LabTheme.mint).frame(width: 8, height: 8).opacity(isTouching ? 1 : 0.25) }
    }

    private func touchGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                sharpness = bounded(Double(gesture.location.x / max(1, size.width)), to: 0...1, fallback: 0.5)
                intensity = bounded(Double(1 - gesture.location.y / max(1, size.height)), to: 0...1, fallback: 0.5)
                if !gestureSessionStarted {
                    gestureSessionStarted = true
                    isTouching = true
                    haptics.beginPad(intensity: intensity, sharpness: sharpness)
                } else {
                    haptics.updatePad(intensity: intensity, sharpness: sharpness)
                }
            }
            .onEnded { _ in
                gestureSessionStarted = false
                isTouching = false
                haptics.endPad()
            }
    }
}

private struct PadDots: View {
    var body: some View {
        Canvas { context, size in
            for column in 1..<6 {
                for row in 1..<6 {
                    let point = CGPoint(x: size.width * CGFloat(column) / 6,
                                        y: size.height * CGFloat(row) / 6)
                    let dot = CGRect(x: point.x - 1.3, y: point.y - 1.3, width: 2.6, height: 2.6)
                    context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.15)))
                }
            }
        }
    }
}
