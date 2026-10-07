import SwiftUI

struct HapticLayersView: View {
    @EnvironmentObject private var haptics: HapticController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("再生中のレイヤー · \(haptics.layers.count)/4")
                .font(.system(size: 14, weight: .semibold))
            if haptics.layers.isEmpty {
                Text("持続する触感にクリックを重ね、各レイヤーの強さと鋭さを調整できます。")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            }
            ForEach(haptics.layers) { layer in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(layer.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer()
                        Button { haptics.stopLayer(layer.id) } label: { Image(systemName: "stop.circle") }
                            .accessibilityLabel("\(layer.name)だけ停止")
                    }
                    HStack {
                        Text("強さ").font(.system(size: 11))
                        Slider(value: Binding(get: {
                            haptics.layers.first(where: { $0.id == layer.id })?.gain ?? layer.gain
                        }, set: { value in
                            let current = haptics.layers.first(where: { $0.id == layer.id }) ?? layer
                            haptics.updateLayer(layer.id, gain: value, sharpness: current.sharpness)
                        }), in: 0...1).accessibilityLabel("\(layer.name)の強さ")
                    }
                    HStack {
                        Text("鋭さ").font(.system(size: 11))
                        Slider(value: Binding(get: {
                            haptics.layers.first(where: { $0.id == layer.id })?.sharpness ?? layer.sharpness
                        }, set: { value in
                            let current = haptics.layers.first(where: { $0.id == layer.id }) ?? layer
                            haptics.updateLayer(layer.id, gain: current.gain, sharpness: value)
                        }), in: -1...1).accessibilityLabel("\(layer.name)の鋭さ調整")
                    }
                }
            }
            if !haptics.layers.isEmpty {
                Button("すべて停止") { haptics.stop() }.accessibilityIdentifier("layers.stopAll")
            }
        }.tint(LabTheme.mint).labPanel()
    }
}
