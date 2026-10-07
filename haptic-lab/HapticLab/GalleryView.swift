import SwiftUI
import UniformTypeIdentifiers

struct GalleryView: View {
    @EnvironmentObject private var haptics: HapticController
    @AppStorage("favoritePresetIDs") private var favorites = ""
    @State private var presets: [HapticPatternSpec] = []
    @State private var selectedCategory = "all"
    @State private var catalogError: String?
    @State private var layering = false
    @State private var loopTexture = false
    @State private var importingAHAP = false
    @State private var exportingAHAP = false
    @State private var ahapFile = AHAPFile(data: Data())
    @State private var exportName = "pattern.ahap"

    private let filters: [(String, String)] = [
        ("all", "すべて"), ("tap", "クリック"), ("rhythm", "リズム"),
        ("texture", "持続"), ("favorites", "お気に入り")
    ]

    private var favoriteIDs: Set<String> { Set(favorites.split(separator: ",").map(String.init)) }
    private var visiblePresets: [HapticPatternSpec] {
        presets.filter {
            selectedCategory == "all" || $0.category == selectedCategory ||
                (selectedCategory == "favorites" && favoriteIDs.contains($0.id))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                SectionIntro(eyebrow: "FEEL THE DIFFERENCE", title: "カチッ。ふわっ。\nその違いを、手の中で。",
                             detail: "見本を押して、iPhoneが作る触感を比べてみよう。")
                TactileWave(intensity: 0.75, sharpness: 0.3)
                    .frame(height: 50)
                    .padding(.top, 3)
                HStack {
                    Label("\(presets.count)の見本", systemImage: "sparkles")
                    Spacer()
                    Text("見本は音を鳴らしません")
                }
                .font(.system(size: 11))
                .foregroundStyle(LabTheme.muted)
            }
            .labPanel()

            VStack(alignment: .leading, spacing: 12) {
                Toggle("再生中の触感に重ねる", isOn: $layering)
                    .accessibilityIdentifier("layers.enabled")
                Toggle("持続の見本を繰り返す（最大60秒）", isOn: $loopTexture)
                    .font(.system(size: 12)).accessibilityIdentifier("layers.loop")
                Button { importingAHAP = true } label: {
                    Label("AHAPを読み込んで再生", systemImage: "square.and.arrow.down")
                }.accessibilityIdentifier("ahap.import")
                Text("見本を長押しするとAHAPを書き出せます。")
                    .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
            }.tint(LabTheme.mint).labPanel()
            HapticLayersView()

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.0) { filter in
                        Button { selectedCategory = filter.0 } label: {
                            Text(filter.1)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .foregroundStyle(selectedCategory == filter.0 ? LabTheme.background : LabTheme.muted)
                                .background(selectedCategory == filter.0 ? LabTheme.mint : LabTheme.panel, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("filter.\(filter.0)")
                    }
                }
            }
            .scrollIndicators(.hidden)

            if let catalogError {
                Text(catalogError).font(.system(size: 13)).foregroundStyle(LabTheme.coral).labPanel()
            } else if visiblePresets.isEmpty {
                Text("見本のハートを押すと、ここに保存されます。")
                    .font(.system(size: 13)).foregroundStyle(LabTheme.muted).labPanel()
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(visiblePresets) { preset in
                    presetCard(preset)
                }
            }

            DisclosureGroup {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(SystemFeedback.allCases) { feedback in
                        Button { haptics.playSystem(feedback) } label: {
                            Text(feedback.title)
                                .font(.system(size: 12, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(LabTheme.elevated, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 16)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text("iOS標準の触感も比べる").font(.system(size: 14, weight: .semibold))
                    Text("軽い・重い・選択・成功など、9種類")
                        .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                }
            }
            .tint(LabTheme.mint)
            .labPanel()
        }
        .task {
            do { presets = try PatternCatalog.load() }
            catch { catalogError = error.localizedDescription }
        }
        .fileImporter(isPresented: $importingAHAP, allowedContentTypes: [.resonAHAP, .json]) { result in
            do {
                let url = try result.get()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 2 * 1_024 * 1_024 else { throw PatternError.invalid("AHAPは2 MB以内で選んでください。") }
                let document = try HapticAHAP(data: Data(contentsOf: url))
                let name = url.deletingPathExtension().lastPathComponent
                if layering { haptics.addAHAPLayer(document, name: name) }
                else { haptics.playAHAP(document, name: name) }
            } catch { haptics.message = error.localizedDescription }
        }
        .fileExporter(isPresented: $exportingAHAP, document: ahapFile,
                      contentType: .resonAHAP, defaultFilename: exportName) { result in
            if case .failure(let error) = result { haptics.message = error.localizedDescription }
        }
    }

    private func presetCard(_ preset: HapticPatternSpec) -> some View {
        let color = LabTheme.accent(for: preset.category)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: preset.symbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(color)
                Spacer()
                Button { toggleFavorite(preset.id) } label: {
                    Image(systemName: favoriteIDs.contains(preset.id) ? "heart.fill" : "heart")
                        .font(.system(size: 15))
                        .foregroundStyle(favoriteIDs.contains(preset.id) ? LabTheme.coral : LabTheme.muted)
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(preset.name)をお気に入り\(favoriteIDs.contains(preset.id) ? "から外す" : "に追加")")
            }
            Button {
                let loop = loopTexture && preset.category == "texture"
                if layering { haptics.addLayer(preset, loop: loop) }
                else { haptics.play(preset, loop: loop) }
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    Text(preset.name).font(.system(size: 16, weight: .bold))
                    Text(preset.subtitle)
                        .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                        .frame(minHeight: 30, alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                    TactileWave(intensity: 0.55,
                                sharpness: preset.events.first?.sharpness ?? 0.5, color: color)
                        .frame(height: 26)
                    HStack {
                        Text(preset.duration < 0.2 ? "一瞬" : String(format: "%.1f 秒", preset.duration))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(LabTheme.muted)
                        Spacer()
                        Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(preset.name)を再生。\(preset.subtitle)")
            .accessibilityIdentifier("preset.\(preset.id)")
        }
        .padding(15)
        .background(LabTheme.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.045), lineWidth: 1)
        }
        .contextMenu {
            Button {
                do {
                    ahapFile = AHAPFile(data: try HapticAHAP.encode(preset))
                    exportName = preset.id + ".ahap"
                    exportingAHAP = true
                } catch { haptics.message = error.localizedDescription }
            } label: { Label("AHAPを書き出す", systemImage: "square.and.arrow.up") }
            Button {
                haptics.addLayer(preset, loop: loopTexture && preset.category == "texture")
            } label: { Label("レイヤーとして追加", systemImage: "square.stack.3d.up") }
        }
    }

    private func toggleFavorite(_ id: String) {
        var ids = favoriteIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favorites = ids.sorted().joined(separator: ",")
    }
}
