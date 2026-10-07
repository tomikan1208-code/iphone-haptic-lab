import SwiftUI

struct MusicAnalysisDeletionView: View {
    let recordID: String
    @EnvironmentObject private var library: MusicLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var confirming = false
    @State private var errorText: String?
    private var record: MusicRecord? { library.records.first { $0.id == recordID } }
    var body: some View {
        List {
            Section {
                if let record {
                    ForEach(record.analysisVariants.reversed()) { variant in
                        Button {
                            if !selected.insert(variant.id).inserted { selected.remove(variant.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(variant.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(LabTheme.mint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(variant.title).font(.subheadline)
                                    Text(variant.dateText + (record.selectedVariantID == variant.id ? " · 使用中" : ""))
                                        .font(.caption).foregroundStyle(LabTheme.muted)
                                }
                            }.foregroundStyle(.white)
                        }.accessibilityIdentifier("analysis.deleteOption.\(variant.id)")
                            .accessibilityValue(selected.contains(variant.id) ? "選択済み" : "未選択")
                    }
                    Button(selected.count == record.analysisVariants.count ? "選択を解除" : "すべて選択") {
                        selected = selected.count == record.analysisVariants.count ? [] : Set(record.analysisVariants.map(\.id))
                    }.accessibilityIdentifier("analysis.selectAll")
                }
            } header: { Text(record?.selection.title ?? "保存した解析") }
            Section {
                Button("選択した解析を削除（\(selected.count)件）", role: .destructive) { confirming = true }
                    .disabled(selected.isEmpty).accessibilityIdentifier("analysis.deleteSelected")
                Text("選んだ解析結果だけをiPhoneから削除します。残した解析と調整値は保持します。すべて削除すると、この曲の履歴・調整値・音源のアプリ内コピーも削除します。PCの保存データは別管理です。")
                    .font(.caption).foregroundStyle(LabTheme.muted)
                if let errorText { Text(errorText).foregroundStyle(LabTheme.coral) }
            }
        }.scrollContentBackground(.hidden).background(LabTheme.background).tint(LabTheme.mint)
            .navigationTitle("削除する解析を選択").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } } }
            .alert("選択した\(selected.count)件の解析を削除しますか？", isPresented: $confirming) {
                Button("削除", role: .destructive) {
                    do { try library.deleteVariants(selected, for: recordID); dismiss() }
                    catch { errorText = error.localizedDescription }
                }
                Button("キャンセル", role: .cancel) {}
            }
    }
}
