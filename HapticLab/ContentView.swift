import SwiftUI

enum LabTab: String, CaseIterable, Identifiable {
    case gallery, experiment, pad, guide
    var id: String { rawValue }

    var title: String {
        switch self {
        case .gallery: return "見本"
        case .experiment: return "作る"
        case .pad: return "触れる"
        case .guide: return "使い方"
        }
    }

    var symbol: String {
        switch self {
        case .gallery: return "square.grid.2x2"
        case .experiment: return "slider.horizontal.3"
        case .pad: return "hand.draw"
        case .guide: return "questionmark.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var haptics: HapticController
    @State private var tab: LabTab = .gallery

    var body: some View {
        VStack(spacing: 0) {
            header
            if let message = haptics.message {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").foregroundStyle(LabTheme.mint)
                    Text(message)
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { haptics.message = nil } label: {
                        Image(systemName: "xmark").padding(4)
                    }
                    .accessibilityLabel("メッセージを閉じる")
                }
                .padding(12)
                .background(LabTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
            ScrollView {
                Group {
                    switch tab {
                    case .gallery: GalleryView()
                    case .experiment: ExperimentView()
                    case .pad: TouchPadView()
                    case .guide: GuideView()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .id(tab)
            playerBar
            navigationBar
        }
        .background(LabTheme.background.ignoresSafeArea())
        .foregroundStyle(.white)
        .onChange(of: tab) { _ in haptics.stop() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 9) {
                Image(systemName: "waveform")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LabTheme.mint)
                Text("触感ラボ").font(.system(size: 19, weight: .bold))
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(haptics.supportsHaptics ? LabTheme.mint : LabTheme.muted)
                    .frame(width: 5, height: 5)
                Text(haptics.supportsHaptics ? "触感を再生できます" : "体験には実機が必要")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(LabTheme.muted)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(LabTheme.panel, in: Capsule())
            .accessibilityIdentifier("runtime.status")
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 20)
    }

    private var playerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: haptics.isPlaying ? "waveform" : "pause.circle")
                .foregroundStyle(haptics.isPlaying ? LabTheme.mint : LabTheme.muted)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(haptics.isPlaying ? "PLAYING" : "READY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(LabTheme.muted)
                Text(haptics.activeName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .accessibilityIdentifier("playback.status")
            }
            Spacer(minLength: 0)
            Button { haptics.stop() } label: {
                Label("停止", systemImage: "stop.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LabTheme.coral)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                    .background(LabTheme.coral.opacity(0.10), in: Capsule())
            }
            .accessibilityLabel("すべての振動を停止")
            .accessibilityIdentifier("playback.stop")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(LabTheme.panel)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            ForEach(LabTab.allCases) { item in
                Button { tab = item } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 18))
                        Text(item.title).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(tab == item ? LabTheme.mint : LabTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab.\(item.rawValue)")
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .background(LabTheme.background)
    }
}
