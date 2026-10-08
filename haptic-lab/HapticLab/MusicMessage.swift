import SwiftUI

struct MusicMessage: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(LabTheme.mint)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { Image(systemName: "xmark").foregroundStyle(LabTheme.muted).padding(4) }
                .accessibilityLabel("メッセージを閉じる")
        }.padding(14).background(LabTheme.elevated, in: RoundedRectangle(cornerRadius: 13))
    }
}
