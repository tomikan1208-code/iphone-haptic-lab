import Foundation
import SwiftUI

struct MusicLibrarySnapshot: Codable {
    var version = 1
    var records: [MusicRecord] = []

    func validated() throws -> MusicLibrarySnapshot {
        guard version == 1, records.count <= 5_000,
              Set(records.map(\.id)).count == records.count else { throw MusicError.storage("保存した曲を読み込めません。保存データを確認してください。") }
        for record in records {
            guard !record.id.isEmpty, record.trackBytes >= 0,
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

    func write(_ records: [MusicRecord]) throws {
        let snapshot = try MusicLibrarySnapshot(records: records).validated()
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
        for (directory, names) in [(tracks, Set(records.compactMap(\.trackFilename))),
                                   (media, Set(records.compactMap(\.mediaFilename)))] {
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
            records = try disk.load().records
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

    func saveHistory(_ selection: MusicSelection) {
        do {
            var next = records
            if let index = next.firstIndex(where: { $0.id == selection.id }) {
                next[index].lastPlayedAt = Date()
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
        do { try persist(next) } catch { message = error.localizedDescription }
    }

    func delete(_ record: MusicRecord) throws {
        if preparation?.selection.id == record.id { cancelPreparation() }
        try persist(records.filter { $0.id != record.id })
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
        try disk.write(next)
        records = next
    }

    private func commit(_ track: MusicHapticTrack, selection: MusicSelection, localURL: URL?) throws {
        let track = try track.validated()
        let data = try JSONEncoder().encode(track)
        let filename = "\(UUID().uuidString).json"
        let trackURL = disk.tracks.appendingPathComponent(filename)
        let mediaFilename = localURL.map { "\(UUID().uuidString).\($0.pathExtension)" }
        let mediaURL = mediaFilename.map { disk.media.appendingPathComponent($0) }
        do {
            try data.write(to: trackURL, options: .atomic)
            if let localURL, let mediaURL { try FileManager.default.moveItem(at: localURL, to: mediaURL) }
            var record = self.record(for: selection) ?? MusicRecord(selection: selection)
            record.selection = selection
            record.selection.duration = track.duration
            record.trackFilename = filename
            record.trackBytes = data.count
            record.analysis = track.analysis
            record.mediaFilename = mediaFilename
            var next = records.filter { $0.id != selection.id }
            next.append(record)
            try persist(next)
        } catch {
            try? FileManager.default.removeItem(at: trackURL)
            if let mediaURL { try? FileManager.default.removeItem(at: mediaURL) }
            throw error
        }
        try disk.removeOrphans(records: records)
    }
}
