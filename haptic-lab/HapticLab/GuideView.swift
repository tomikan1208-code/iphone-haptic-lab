import SwiftUI

struct GuideView: View {
    @EnvironmentObject private var haptics: HapticController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionIntro(eyebrow: "A LITTLE GUIDE", title: "触感を楽しむコツ。",
                         detail: "同じiPhoneでも、持ち方と設定で感じ方が変わります。")
            tip("hand.raised", title: "手に持って比べる",
                text: "軽く手に持ち、見本を1つずつ再生してみてください。ケースや机に置いた状態でも感じ方が変わります。")
            tip("music.note", title: "好きな音楽で試す",
                text: "「検索」から好きな曲を選んでください。初回だけ振動を作成し、2回目から保存した振動を使います。保存した曲は「再生リスト」の「作成済み」から開けます。")
            tip("slider.horizontal.3", title: "「強さ」と「鋭さ」は別もの",
                text: "強さは振動の大きさ。鋭さを上げると、柔らかい感触から、くっきりしたクリック感へ近づきます。")
            tip("button.programmable", title: "ホームボタンの感触を探す",
                text: "「振動サンプル」の「クリック」とiOS標準の「硬い」を比べ、「振動を調整」で一瞬の振動を調整してみましょう。ホームボタンと同じ感触の完全再現は保証できません。")
            tip("stop.circle", title: "いつでも停止",
                text: "画面下の「停止」で振動が止まります。タブの切り替え、画面ロック、他アプリへの移動でも停止します。中断後に勝手に再生を再開しません。")

            VStack(alignment: .leading, spacing: 12) {
                Label("振動が出ないとき", systemImage: "questionmark.circle")
                    .font(.system(size: 16, weight: .bold))
                Text("設定 → アクセシビリティ → タッチ → バイブレーションがオンか確認してください。アプリを開いた状態で再生し、必要なら一度アプリを閉じて開き直してください。")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                Text(haptics.supportsHaptics ? "この端末はカスタム振動に対応しています。" : "この環境はカスタム振動に対応していません。体験にはiPhone実機が必要です。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LabTheme.mint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .labPanel()
            Text("Reson  ·  音楽と触感を手の中へ")
                .font(.system(size: 10)).foregroundStyle(LabTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 5)
        }
    }

    private func tip(_ symbol: String, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20)).foregroundStyle(LabTheme.mint)
                .frame(width: 25).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(text).font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .labPanel()
    }
}
