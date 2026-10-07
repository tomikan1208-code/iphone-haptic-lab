import Foundation
import SwiftUI

struct MusicLibrarySnapshot: Codable {
    var version = 1
    var records: [MusicRecord] = []
    var globalSettings = MusicSettings()

    private enum CodingKeys: String, CodingKey { case version, records, globalSettings }
    init(version: Int = 1, records: [MusicRecord] = [], globalSettings: MusicSettings = .init()) {
        self.version = version
        self.records = records
        self.globalSettings = globalSettings.normalized
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        records = try values.decode([MusicRecord].self, forKey: .records)
        globalSettings = try values.decodeIfPresent(MusicSettings.self, forKey: .globalSettings)?.normalized ?? MusicSettings()
    }

    func validated() throws -> MusicLibrarySnapshot {
        guard version == 1, records.count <= 5_000,
              Set(records.map(\.id)).count == records.count else { throw MusicError.storage("保存した曲を読み込めません。保存データを確認してください。") }
        for record in records {
            let variants = record.analysisVariants
            guard !record.id.isEmpty, record.trackBytes >= 0,
                  variants.count <= 200, Set(variants.map(\.id)).count == variants.count,
                  variants.allSatisfy({ !$0.id.isEmpty && $0.trackBytes >= 0 && MusicLibraryDisk.safeFilename($0.trackFilename)
                      && ($0.mediaFilename.map(MusicLibraryDisk.safeFilename) ?? true) }),
                  record.activeVariantID.map({ id in variants.contains { $0.id == id } }) ?? true,
                  [record.trackFilename, record.mediaFilename].compactMap({ $0 }).allSatisfy(MusicLibraryDisk.safeFilename) else {
                throw MusicError.storage("曲の保存先が不正です。")
            }
            if record.selection.kind == .youtube {
                guard let id = record.selection.videoID, MusicSelection.validVideoID(id) else { throw MusicError.corruptTrack }
            }
        }
        return self
    }
}

struct MusicLibraryDisk {
    let root: URL
    var tracks: URL { root.appendingPathComponent("Tracks", isDirectory: true) }
    var media: URL { root.appendingPathComponent("Media", isDirectory: true) }
    var working: URL { root.appendingPathComponent("Working", isDirectory: true) }
    var index: URL { root.appendingPathComponent("library.json") }

    static func safeFilename(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9-]+\\.[A-Za-z0-9]+$", options: .regularExpression) != nil
    }

    func initialize() throws {
        for directory in [root, tracks, media, working] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var resource = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resource.setResourceValues(values)
    }

    func load() throws -> MusicLibrarySnapshot {
        guard FileManager.default.fileExists(atPath: index.path) else { return MusicLibrarySnapshot() }
        return try JSONDecoder().decode(MusicLibrarySnapshot.self, from: Data(contentsOf: index)).validated()
    }

    func write(_ records: [MusicRecord], globalSettings: MusicSettings = .init()) throws {
        let snapshot = try MusicLibrarySnapshot(records: records, globalSettings: globalSettings).validated()
        try JSONEncoder().encode(snapshot).write(to: index, options: .atomic)
    }

    func track(_ record: MusicRecord) throws -> MusicHapticTrack {
        guard let filename = record.trackFilename, Self.safeFilename(filename) else { throw MusicError.missingTrack }
        do {
            return try JSONDecoder().decode(MusicHapticTrack.self, from: Data(contentsOf: tracks.appendingPathComponent(filename))).validated()
        } catch { throw MusicError.corruptTrack }
    }

    func mediaURL(_ record: MusicRecord) -> URL? {
        guard let name = record.mediaFilename, Self.safeFilename(name) else { return nil }
        return media.appendingPathComponent(name)
    }

    // Recover interrupted commits/deletions without removing any referenced data.
    func removeOrphans(records: [MusicRecord]) throws {
        let variants = records.flatMap(\.analysisVariants)
        for (directory, names) in [(tracks, Set(variants.map(\.trackFilename)).union(records.compactMap(\.trackFilename))),
                                   (media, Set(variants.compactMap(\.mediaFilename)).union(records.compactMap(\.mediaFilename)))] {
            for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                if !names.contains(url.lastPathComponent) { try FileManager.default.removeItem(at: url) }
            }
        }
    }
}

struct MusicPreparationProgress {
    let id: UUID
    let selection: MusicSelection
    var fraction: Double = 0
    var message = "解析の準備中"
    let startedAt = Date()
    var remainingText: String {
        let elapsed = Date().timeIntervalSince(startedAt)
        guard fraction > 0.1, fraction < 0.95, elapsed > 2 else { return "" }
        return " · 残り目安 \(Int(min(86_400, elapsed * (1 - fraction) / fraction)))秒"
    }
}

struct MusicPreparationServices: Sendable {
    typealias Progress = @Sendable (Double, String) -> Void
    var youtubeAudioURL: @Sendable (MusicSelection) async throws -> URL = { try await YouTubeMedia.audioURL(for: $0) }
    var download: @Sendable (URL, URL, @escaping Progress) async throws -> URL = { source, destination, progress in
        if YouTubeAudioDownload.isYouTubeAudio(source) {
            return try await YouTubeAudioDownload.download(source, to: destination, progress: progress)
        }
        return try await MusicMediaDownload(destination: destination, progress: progress).download(source)
    }
    var analyzeOnPC: @Sendable (PCServerConnection, MusicSelection, URL?, MusicGenerationStyle, MusicArrangement,
                                @escaping Progress) async throws -> MusicHapticTrack = { connection, selection, file, style, profile, progress in
        try await PCAnalysisClient(connection: connection).analyze(selection: selection, file: file,
            style: style, profile: profile, progress: progress)
    }
}

@MainActor
final class MusicLibrary: ObservableObject {
    @Published private(set) var globalSettings = MusicSettings()
    @Published private(set) var records: [MusicRecord] = []
    @Published private(set) var preparation: MusicPreparationProgress?
    @Published var message: String?
    @Published private(set) var recentlyPreparedID: String?
    let disk: MusicLibraryDisk
    private var storageAvailable = true
    private var preparationTask: Task<Void, Never>?
    private var worker: Task<MusicHapticTrack, Error>?
    private let services: MusicPreparationServices

    var prepared: [MusicRecord] { records.filter(\.isPrepared).sorted { $0.createdAt > $1.createdAt } }
    var history: [MusicRecord] { records.filter { $0.lastPlayedAt != nil }.sorted { $0.lastPlayedAt! > $1.lastPlayedAt! } }

    init(root: URL? = nil, services: MusicPreparationServices = .init()) {
        self.services = services
        let directory = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicLibrary", isDirectory: true)
        disk = MusicLibraryDisk(root: directory)
        do {
            try disk.initialize()
            let snapshot = try disk.load()
            records = snapshot.records
            globalSettings = snapshot.globalSettings
            try disk.removeOrphans(records: records)
            for url in try FileManager.default.contentsOfDirectory(at: disk.working, includingPropertiesForKeys: nil) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            // Preserve the original index if decoding fails, instead of overwriting it with an empty library.
            storageAvailable = false
            message = "保存データを読み込めませんでした。\(error.localizedDescription)"
        }
    }

    func record(for selection: MusicSelection) -> MusicRecord? { records.first { $0.id == selection.id } }

    func settings(for id: String) -> MusicSettings {
        guard let record = records.first(where: { $0.id == id }), record.hasIndividualSettings else { return globalSettings }
        return record.settings.normalized
    }

    func saveGlobalSettings(_ settings: MusicSettings, adoptingFor id: String? = nil) {
        do {
            guard storageAvailable else { throw MusicError.storage("保存先を利用できません。") }
            let settings = settings.normalized
            var next = records
            if let id, let index = next.firstIndex(where: { $0.id == id }) {
                next[index].settings = settings
                next[index].usesGlobalSettings = true
            }
            try disk.write(next, globalSettings: settings)
            globalSettings = settings
            records = next
        } catch { message = error.localizedDescription }
    }

    func resetSettingsToGlobal(id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        var next = records
        next[index].settings = globalSettings
        next[index].usesGlobalSettings = true
        do { try persist(next) } catch { message = error.localizedDescription }
    }

    func saveHistory(_ selection: MusicSelection) {
        do {
            var next = records
            if let index = next.firstIndex(where: { $0.id == selection.id }) {
                next[index].lastPlayedAt = Date()
                var variants = next[index].analysisVariants
                if let active = variants.firstIndex(where: { $0.id == next[index].selectedVariantID }) {
                    variants[active].lastUsedAt = Date()
                    next[index].variants = variants
                }
            } else {
                var record = MusicRecord(selection: selection)
                record.lastPlayedAt = Date()
                next.append(record)
            }
            try persist(next)
        } catch { message = error.localizedDescription }
    }

    func saveSettings(_ settings: MusicSettings, id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        var next = records
        next[index].settings = settings.normalized
        next[index].usesGlobalSettings = false
        do { try persist(next) } catch { message = error.localizedDescription }
    }

    func delete(_ record: MusicRecord) throws {
        if preparation?.selection.id == record.id { cancelPreparation() }
        try persist(records.filter { $0.id != record.id })
        try disk.removeOrphans(records: records)
    }

    @discardableResult
    func selectVariant(_ variantID: String, for id: String) throws -> MusicHapticTrack {
        guard let index = records.firstIndex(where: { $0.id == id }),
              let variant = records[index].analysisVariants.first(where: { $0.id == variantID }) else { throw MusicError.missingTrack }
        var next = records
        var variants = next[index].analysisVariants
        let position = variants.firstIndex(where: { $0.id == variantID })!
        variants[position].lastUsedAt = Date()
        next[index].variants = variants
        next[index].useVariant(variant)
        let track = try disk.track(next[index])
        try persist(next)
        return track
    }

    func deleteVariants(_ variantIDs: Set<String>, for id: String) throws {
        guard let index = records.firstIndex(where: { $0.id == id }), !variantIDs.isEmpty else { return }
        let record = records[index]
        guard variantIDs.isSubset(of: Set(record.analysisVariants.map(\.id))) else { throw MusicError.missingTrack }
        let remaining = record.analysisVariants.filter { !variantIDs.contains($0.id) }
        if remaining.isEmpty { try delete(record); return }
        var next = records
        next[index].variants = remaining
        if let selected = remaining.first(where: { $0.id == record.selectedVariantID }) {
            next[index].useVariant(selected)
        } else if let fallback = remaining.max(by: { ($0.lastUsedAt ?? $0.createdAt) < ($1.lastUsedAt ?? $1.createdAt) }) {
            next[index].useVariant(fallback)
        }
        try persist(next)
        try disk.removeOrphans(records: records)
    }

    func prepare(_ selection: MusicSelection, audioFile: URL? = nil, audioDownloadURL: URL? = nil,
                 method: MusicAnalysisMethod = .pc, style: MusicGenerationStyle = .arranged,
                 profile: MusicArrangement = .standard,
                 quality: MusicAnalysisQuality = .precision,
                 connection: PCServerConnection? = nil) {
        var correctedSelection = selection
        // Cached duration was previously replaced with the faulty analysis length.
        // It cannot validate a repair downloaded directly from the same video ID.
        if selection.kind == .youtube, method == .device, audioFile == nil, audioDownloadURL == nil,
           record(for: selection)?.requiresAudioReanalysis == true { correctedSelection.duration = nil }
        let selection = correctedSelection
        if method == .device, quality != .precision {
            message = "iPhoneでは精密解析を選んでください。高速解析は利用できません。"
            return
        }
        if style == .arranged && method != .pc {
            message = "AI編曲はPCで実行します。PCの接続設定を確認してください。"
            return
        }
        guard preparation == nil, storageAvailable else {
            message = storageAvailable ? "解析中の曲が終わってから追加してください。" : "保存先を利用できません。"
            return
        }
        if let duration = selection.duration, duration > MusicHapticTrack.maximumDuration {
            message = MusicError.tooLong.localizedDescription
            return
        }
        let jobID = UUID()
        let folder = disk.working.appendingPathComponent(jobID.uuidString, isDirectory: true)
        let suffix = audioFile?.pathExtension.lowercased() ?? URL(string: selection.url)?.pathExtension.lowercased() ?? "m4a"
        let localURL = folder.appendingPathComponent("source.\(suffix.isEmpty ? "m4a" : suffix)")
        preparation = MusicPreparationProgress(id: jobID, selection: selection)
        message = nil
        recentlyPreparedID = nil
        let report: @Sendable (Double, String) -> Void = { [weak self] fraction, message in
            Task { @MainActor [weak self] in
                guard self?.preparation?.id == jobID else { return }
                self?.preparation?.fraction = bounded(fraction, to: 0...1, fallback: 0)
                self?.preparation?.message = message
            }
        }
        let services = self.services
        let worker = Task.detached(priority: .userInitiated) {
            let started = Date()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Task.checkCancellation()
            if method == .pc, selection.kind == .youtube, audioFile == nil, audioDownloadURL == nil {
                guard let connection else { throw MusicError.network("メニューの「解析方法・PCサーバー」でPCを設定してください。") }
                return try await services.analyzeOnPC(connection, selection, nil, style, profile, report)
            }
            if let audioFile {
                let access = audioFile.startAccessingSecurityScopedResource()
                defer { if access { audioFile.stopAccessingSecurityScopedResource() } }
                let size = try audioFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard Int64(size) <= MusicAnalyzer.maximumBytes else { throw MusicError.tooLong }
                try FileManager.default.copyItem(at: audioFile, to: localURL)
            } else if let url = audioDownloadURL ?? (selection.kind == .remote ? URL(string: selection.url) : nil) {
                _ = try await services.download(url, localURL, report)
            } else if selection.kind == .youtube {
                report(0.01, "動画の音声を準備しています")
                let url = try await services.youtubeAudioURL(selection)
                try Task.checkCancellation()
                _ = try await services.download(url, localURL, report)
            } else { throw MusicError.unsupportedMedia }
            try Task.checkCancellation()
            if method == .pc {
                guard let connection else { throw MusicError.network("PCサーバーを設定してください。") }
                return try await services.analyzeOnPC(connection, selection, localURL, style, profile, report)
            }
            report(0.1, quality == .precision ? "帯域別の精密解析を開始しています" : "高速解析を開始しています")
            let analysisStarted = Date()
            var track = try await MusicAnalyzer.analyze(localURL, quality: quality, progress: report)
            track.analysis = MusicAnalysisInfo(engine: "device", elapsedSeconds: 0, sampleRate: Int(quality.sampleRate),
                hopMilliseconds: quality.hopMilliseconds, fftSize: quality.fftSize, style: style,
                decoderVersion: MusicAnalyzer.decoderVersion, quality: quality)
            // Preserve natural timing and crescendos for orchestral music instead of applying a fixed beat grid.
            if profile == .orchestral { track = try MusicComposer.orchestral(track) }
            else if style == .musical { track = try MusicComposer.compose(track) }
            track.analysis = MusicAnalysisInfo(engine: "device", elapsedSeconds: Date().timeIntervalSince(started),
                sampleRate: Int(quality.sampleRate), hopMilliseconds: quality.hopMilliseconds, fftSize: quality.fftSize,
                style: style, tempoBPM: track.analysis?.tempoBPM, profile: profile,
                decoderVersion: MusicAnalyzer.decoderVersion, quality: quality)
            track.analysis?.processingSeconds = Date().timeIntervalSince(analysisStarted)
            return track
        }
        self.worker = worker
        preparationTask = Task { [weak self] in
            defer { try? FileManager.default.removeItem(at: folder) }
            do {
                let track = try await worker.value
                try Task.checkCancellation()
                guard let self, self.preparation?.id == jobID else { return }
                if let duration = selection.duration, abs(duration - track.duration) > max(1, duration * 0.015) {
                    throw MusicError.storage("動画と音源の長さが一致しません。同じバージョン・同じ開始位置の音源を選んでください。")
                }
                report(0.98, "振動を保存しています")
                try self.commit(track, selection: selection, localURL: selection.kind == .file ? localURL : nil)
                // Only publish completion after deleting the analysis-only audio.
                try FileManager.default.removeItem(at: folder)
                self.recentlyPreparedID = selection.id
                let elapsed = track.analysis.map { String(format: "（%.1f秒）", $0.elapsedSeconds) } ?? ""
                self.message = "振動を保存しました\(elapsed)。次回から解析せずに再生できます。"
            } catch {
                if !(error is CancellationError), let self, self.preparation?.id == jobID {
                    self.message = error.localizedDescription
                }
            }
            guard let self, self.preparation?.id == jobID else { return }
            self.preparation = nil
            self.worker = nil
            self.preparationTask = nil
        }
    }

    func cancelPreparation() {
        worker?.cancel()
        preparationTask?.cancel()
        worker = nil
        preparationTask = nil
        preparation = nil
        message = "解析をキャンセルしました。"
    }

    private func persist(_ next: [MusicRecord]) throws {
        guard storageAvailable else { throw MusicError.storage("保存先を利用できません。元の保存データは保持されています。") }
        try disk.write(next, globalSettings: globalSettings)
        records = next
    }

    private func commit(_ track: MusicHapticTrack, selection: MusicSelection, localURL: URL?) throws {
        let track = try track.validated()
        let data = try JSONEncoder().encode(track)
        let filename = "\(UUID().uuidString).json"
        let trackURL = disk.tracks.appendingPathComponent(filename)
        let existing = record(for: selection)
        let reuseMedia = localURL.flatMap { source in
            existing.flatMap { record in disk.mediaURL(record).map { FileManager.default.contentsEqual(atPath: source.path, andPath: $0.path) } }
        } ?? false
        let mediaFilename = reuseMedia ? existing?.mediaFilename : localURL.map { "\(UUID().uuidString).\($0.pathExtension)" }
        let mediaURL = mediaFilename.map { disk.media.appendingPathComponent($0) }
        do {
            try data.write(to: trackURL, options: .atomic)
            if let localURL, let mediaURL, !reuseMedia { try FileManager.default.moveItem(at: localURL, to: mediaURL) }
            var record = self.record(for: selection) ?? MusicRecord(selection: selection)
            var variants = record.analysisVariants
            guard variants.count < 200 else { throw MusicError.storage("この曲の解析結果が200件あります。不要な結果を削除してから追加してください。") }
            record.selection = selection
            record.selection.duration = track.duration
            let variant = MusicAnalysisVariant(id: UUID().uuidString, createdAt: Date(), lastUsedAt: Date(),
                trackFilename: filename, mediaFilename: mediaFilename, trackBytes: data.count, analysis: track.analysis)
            variants.append(variant)
            record.variants = variants
            record.useVariant(variant)
            var next = records.filter { $0.id != selection.id }
            next.append(record)
            try persist(next)
        } catch {
            try? FileManager.default.removeItem(at: trackURL)
            if let mediaURL, !reuseMedia { try? FileManager.default.removeItem(at: mediaURL) }
            throw error
        }
        try disk.removeOrphans(records: records)
    }
}
