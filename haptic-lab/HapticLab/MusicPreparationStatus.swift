import SwiftUI

extension MusicPreparationProgress {
    var stage: Int { fraction < 0.08 ? 0 : (fraction < 0.9 ? 1 : 2) }
    var stageFraction: Double {
        switch stage {
        case 0: return bounded((fraction - 0.02) / 0.06, to: 0...1, fallback: 0)
        case 1: return bounded((fraction - 0.08) / 0.82, to: 0...1, fallback: 0)
        default: return bounded((fraction - 0.9) / 0.1, to: 0...1, fallback: 0)
        }
    }
}

struct MusicPreparationBanner: View {
    let progress: MusicPreparationProgress
    let open: () -> Void
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 10) {
                    ProgressView().tint(LabTheme.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("振動を作成中").font(.system(size: 13, weight: .semibold)).foregroundStyle(LabTheme.mint)
                        Text(progress.selection.title).font(.system(size: 11)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up").foregroundStyle(LabTheme.muted)
                }
                ProgressView(value: progress.stageFraction).tint(LabTheme.mint)
            }.padding(12).background(LabTheme.elevated, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 12).padding(.vertical, 5)
        }.buttonStyle(.plain).accessibilityIdentifier("music.analysisBanner")
    }
}

struct MusicPreparationStatusView: View {
    let selection: MusicSelection?
    let cancel: () -> Void
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    MusicArtwork(selection: selection).frame(height: 170)
                    if let progress = library.preparation {
                        HStack(spacing: 12) {
                            ProgressView().tint(LabTheme.mint)
                            Text("振動を作成中").font(.system(size: 25, weight: .bold)).accessibilityIdentifier("music.preparingTitle")
                        }
                        Text(progress.selection.title).font(.system(size: 16, weight: .semibold)).multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            ForEach(Array(["音声取得", "解析", "振動保存"].enumerated()), id: \.offset) { index, title in
                                VStack(spacing: 7) {
                                    Image(systemName: index < progress.stage ? "checkmark.circle.fill" : "\(index + 1).circle.fill")
                                    Text(title).font(.system(size: 12, weight: .medium))
                                }.foregroundStyle(index <= progress.stage ? LabTheme.mint : LabTheme.muted)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        ProgressView(value: progress.stageFraction).tint(LabTheme.mint)
                        Text(progress.message).font(.system(size: 14)).multilineTextAlignment(.center)
                            .accessibilityIdentifier("music.preparationDetails")
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text("経過 \(Int(context.date.timeIntervalSince(progress.startedAt)))秒")
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(LabTheme.muted)
                        }
                        Text("完了後は保存した振動を使えます。作成中はアプリを開いたままにしてください。")
                            .font(.system(size: 12)).foregroundStyle(LabTheme.muted).multilineTextAlignment(.center)
                        Button("キャンセル", action: cancel).foregroundStyle(LabTheme.muted)
                            .accessibilityIdentifier("music.cancelAnalysis")
                    } else {
                        Text("作成を完了できませんでした").font(.system(size: 21, weight: .semibold))
                        Text(library.message ?? "動画を選んで、もう一度試してください。")
                            .font(.system(size: 14)).multilineTextAlignment(.center)
                        Button("閉じる") { dismiss() }.foregroundStyle(LabTheme.mint)
                    }
                }.padding(24)
            }
            .background(LabTheme.background).foregroundStyle(.white)
            .navigationTitle("初回の振動を作成").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("一覧に戻る") { dismiss() }.accessibilityIdentifier("music.minimizePreparation") } }
        }.preferredColorScheme(.dark)
    }
}

struct YouTubeBrowseRow: View {
    let item: YouTubeBrowseItem
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AsyncImage(url: item.thumbnail) { image in image.resizable().scaledToFill() } placeholder: {
                    ZStack {
                        LabTheme.elevated
                        Image(systemName: item.kind == .channel ? "person.fill" : "music.note.list").foregroundStyle(LabTheme.mint)
                    }
                }.frame(width: item.kind == .channel ? 68 : 108, height: 68).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: item.kind == .channel ? 34 : 8))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                    if !item.subtitle.isEmpty { Text(item.subtitle).font(.system(size: 11)).foregroundStyle(LabTheme.muted).lineLimit(2) }
                    Text(item.kind == .channel ? "チャンネル · 動画と再生リスト" : "再生リスト · 動画を選ぶ")
                        .font(.system(size: 10)).foregroundStyle(LabTheme.mint)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(LabTheme.muted)
            }.padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("youtube.\(item.id)")
    }
}
