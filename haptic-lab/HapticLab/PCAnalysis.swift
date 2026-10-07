import Foundation
import SwiftUI

enum MusicAnalysisMethod: String, Codable, CaseIterable {
    case device, pc
    var title: String { self == .device ? "このiPhone" : "PCで精密解析" }
}

enum MusicAnalysisQuality: String, Codable, CaseIterable, Sendable {
    case standard, precision
    var title: String { self == .precision ? "精密（帯域別）" : "高速" }
    var sampleRate: Double { self == .precision ? 44_100 : 22_050 }
    var fftSize: Int { self == .precision ? 4_096 : 1_024 }
    var hopSize: Int { 441 }
    var hopMilliseconds: Double { Double(hopSize) / sampleRate * 1_000 }
    var detail: String {
        self == .precision
            ? "PCと同じ44.1 kHz・10 ms間隔。低音を3帯域に分け、重い打音と軽い鋭い打音を作り分けます。PCへの接続は不要です。"
            : "22.05 kHz・20 ms間隔で解析します。処理時間と消費電力を抑えたいときに使えます。"
    }
}

enum MusicGenerationStyle: String, Codable, CaseIterable {
    case following, musical, arranged
    var title: String {
        switch self { case .following: return "音に追従"; case .musical: return "リズム中心"; case .arranged: return "AIで編曲" }
    }
    var detail: String {
        switch self {
        case .following: return "低音・音量・打音に合わせて振動します。"
        case .musical: return "テンポに合わせてアクセントと休符を作り、振動が続きすぎないように演出します。"
        case .arranged: return "楽器・サビ・拍・曲の雰囲気をAIで解析し、振動をもう一つの楽器として編曲します。"
        }
    }
}

enum MusicArrangement: String, Codable, CaseIterable {
    case standard, orchestral
    var title: String { self == .standard ? "標準" : "オーケストラ向け" }
}

struct MusicAnalysisInfo: Codable, Equatable {
    let engine: String
    let elapsedSeconds: Double
    let sampleRate: Int
    let hopMilliseconds: Double
    let fftSize: Int
    var serverTrackID: String?
    var style: MusicGenerationStyle? = nil
    var tempoBPM: Double? = nil
    var profile: MusicArrangement? = nil
    var decoderVersion: Int? = nil
    var quality: MusicAnalysisQuality? = nil
    var processingSeconds: Double? = nil
    var pipeline: String? = nil
    var models: [String: String]? = nil
}

struct PCServerConnection: Equatable, Sendable {
    let baseURL: URL
    let token: String

    init(address: String, token: String) throws {
        guard var components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host?.lowercased(), components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/", token.count >= 24,
              token.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw MusicError.network("PCサーバーのURLと接続キーを確認してください。")
        }
        if scheme == "http", !Self.isLocalHost(host) {
            throw MusicError.network("HTTP接続は同じネットワークのPCだけに利用できます。")
        }
        components.path = ""
        guard let url = components.url else { throw MusicError.invalidURL }
        baseURL = url
        self.token = token
    }

    static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4, octets.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return false }
        let parts = octets.compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168)
            || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254)
    }
}

@MainActor
final class AnalysisPreferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var method: MusicAnalysisMethod { didSet { defaults.set(method.rawValue, forKey: "analysis.method") } }
    @Published var address: String { didSet { defaults.set(address, forKey: "analysis.address") } }
    @Published var token: String { didSet { defaults.set(token, forKey: "analysis.token") } }
    @Published var style: MusicGenerationStyle { didSet { defaults.set(style.rawValue, forKey: "analysis.style") } }
    @Published var profile: MusicArrangement { didSet { defaults.set(profile.rawValue, forKey: "analysis.profile") } }
    @Published var quality: MusicAnalysisQuality { didSet { defaults.set(quality.rawValue, forKey: "analysis.quality") } }
    var connection: PCServerConnection? { try? PCServerConnection(address: address, token: token) }
    init() {
        defaults = ProcessInfo.processInfo.arguments.contains("--music-test-library")
            ? UserDefaults(suiteName: "MusicPlayerUITestPreferences")! : .standard
        if ProcessInfo.processInfo.arguments.contains("--reset-music-test-library") {
            for key in ["analysis.method", "analysis.address", "analysis.token", "analysis.style", "analysis.profile", "analysis.quality"] { defaults.removeObject(forKey: key) }
        }
        method = .pc
        address = defaults.string(forKey: "analysis.address") ?? ""
        token = defaults.string(forKey: "analysis.token") ?? ""
        style = .arranged
        profile = MusicArrangement(rawValue: defaults.string(forKey: "analysis.profile") ?? "") ?? .standard
        quality = MusicAnalysisQuality(rawValue: defaults.string(forKey: "analysis.quality") ?? "") ?? .precision
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--music-test-library") {
            address = "http://127.0.0.1:8765"
            token = "UIFixtureConnectionKeyWithoutNetwork"
        }
        #endif
    }
}

struct PCServerHealth: Decodable {
    let protocolVersion: Int
    let youtubeAvailable: Bool
    let profile: String
    let arrangementAvailable: Bool?
}
struct PCStoredTrack: Decodable, Identifiable {
    let id: String
    let title: String
    let duration: Double
    let createdAt: Double
}
private struct PCJob: Decodable {
    let id: String
    let state: String
    let progress: Double
    let message: String
    let track: MusicHapticTrack?
}

struct PCAnalysisClient: Sendable {
    let connection: PCServerConnection
    private static let redirectDelegate = PCSessionDelegate()
    private static let session = URLSession(configuration: .ephemeral, delegate: redirectDelegate, delegateQueue: nil)
    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: connection.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer " + connection.token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90
        return request
    }
    private func checked(_ result: (Data, URLResponse)) throws -> Data {
        guard let response = result.1 as? HTTPURLResponse, result.0.count <= 64 * 1_024 * 1_024 else {
            throw MusicError.network("PCサーバーから正しい応答を受け取れませんでした。")
        }
        guard (200..<300).contains(response.statusCode) else {
            let error = (try? JSONSerialization.jsonObject(with: result.0)) as? [String: Any]
            throw MusicError.network(error?["error"] as? String ?? "PCへ接続できません（\(response.statusCode)）。接続キーとサーバーを確認してください。")
        }
        return result.0
    }
    func health() async throws -> PCServerHealth {
        let data = try checked(await Self.session.data(for: request("health")))
        let health = try JSONDecoder().decode(PCServerHealth.self, from: data)
        guard health.protocolVersion == 1 else { throw MusicError.network("PCサーバーをこのアプリと同じ版へ更新してください。") }
        return health
    }
    func tracks() async throws -> [PCStoredTrack] {
        let data = try checked(await Self.session.data(for: request("tracks")))
        return try JSONDecoder().decode([PCStoredTrack].self, from: data)
    }
    func deleteTrack(_ id: String) async throws {
        guard id.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw MusicError.corruptTrack }
        _ = try checked(await Self.session.data(for: request("tracks/" + id, method: "DELETE")))
    }
    func analyze(selection: MusicSelection, file: URL?, style: MusicGenerationStyle, profile: MusicArrangement, progress: @escaping @Sendable (Double, String) -> Void) async throws -> MusicHapticTrack {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 1_800
        let session = URLSession(configuration: configuration, delegate: Self.redirectDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let health = try await health()
        if style == .arranged, health.arrangementAvailable != true {
            throw MusicError.network("PCにAI解析環境を設定してください。PCでsetup-ml.ps1を実行すると使えます。")
        }
        if file == nil, !health.youtubeAvailable { throw MusicError.network("PCにYouTube取得ツールを設定してください。") }
        let accepted: Data
        if let file {
            progress(0.08, "音源をPCへ送信しています")
            var upload = request("jobs/upload", method: "POST")
            upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            upload.setValue(Data(selection.title.utf8).base64EncodedString(), forHTTPHeaderField: "X-Media-Title")
            upload.setValue(style.rawValue, forHTTPHeaderField: "X-Generation-Style")
            upload.setValue(profile.rawValue, forHTTPHeaderField: "X-Music-Profile")
            accepted = try checked(await session.upload(for: upload, fromFile: file))
        } else {
            guard selection.kind == .youtube, let id = selection.videoID else { throw MusicError.unsupportedMedia }
            var start = request("jobs", method: "POST")
            start.setValue("application/json", forHTTPHeaderField: "Content-Type")
            start.httpBody = try JSONSerialization.data(withJSONObject: ["videoID": id, "title": selection.title, "style": style.rawValue, "profile": profile.rawValue])
            accepted = try checked(await session.data(for: start))
        }
        let job = try JSONDecoder().decode(PCJob.self, from: accepted)
        guard UUID(uuidString: job.id) != nil else { throw MusicError.network("PCの解析IDが正しくありません。") }
        return try await withTaskCancellationHandler(operation: {
            for _ in 0..<1_800 {
                try Task.checkCancellation()
                let data = try checked(await session.data(for: request("jobs/" + job.id)))
                let status = try JSONDecoder().decode(PCJob.self, from: data)
                progress(0.1 + min(1, max(0, status.progress)) * 0.85, status.message)
                if status.state == "done", let track = status.track { return try track.validated() }
                if status.state == "failed" || status.state == "canceled" { throw MusicError.network(status.message) }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            throw MusicError.network("PCの解析が時間内に終わりませんでした。")
        }, onCancel: {
            Task { _ = try? await Self.session.data(for: request("jobs/" + job.id, method: "DELETE")) }
        })
    }
}

private final class PCSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // PC requests contain the connection key. Never forward it through a redirect.
        completionHandler(nil)
    }
}

struct AnalysisSettingsView: View {
    @EnvironmentObject private var preferences: AnalysisPreferences
    @State private var checking = false
    @State private var message: String?
    @State private var tracks: [PCStoredTrack] = []
    @State private var deleting: PCStoredTrack?
    var body: some View {
        Form {
            Section("音楽から振動を編曲") {
                Text("PCでAI解析・編曲").font(.headline)
                Text(preferences.style.detail).font(.system(size: 12)).foregroundStyle(LabTheme.muted)
                Picker("仕上げ", selection: $preferences.profile) {
                    ForEach(MusicArrangement.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("作成時はPCへ接続します。保存後はiPhoneだけで再生できます。作成済みの曲は「振動を作り直す」で新しい編曲に更新できます。")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            }
            Section("PCとの接続") {
                TextField("http://192.168.1.10:8765", text: $preferences.address)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("analysis.address")
                SecureField("PCに表示された接続キー", text: $preferences.token)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("analysis.token")
                Button(checking ? "接続中…" : "接続を確認") { connect() }.disabled(checking)
                    .accessibilityIdentifier("analysis.connect")
                if let message { Text(message).font(.system(size: 12)) }
                Text("同じWi-Fiへ接続してPCサーバーを起動してください。新しく編曲するときにPCへ接続し、作成後の再生には保存した振動を使います。")
                    .font(.system(size: 12)).foregroundStyle(LabTheme.muted)
            }
            if !tracks.isEmpty {
                Section("PCに保存した振動") {
                    ForEach(tracks) { track in
                        HStack {
                            VStack(alignment: .leading) { Text(track.title).font(.system(size: 13)); Text(musicTime(track.duration)).font(.system(size: 11)) }
                            Spacer()
                            Button { deleting = track } label: { Image(systemName: "trash") }.foregroundStyle(LabTheme.coral)
                        }
                    }
                    Text("PCから削除しても、iPhoneに保存した振動は残ります。")
                        .font(.system(size: 11)).foregroundStyle(LabTheme.muted)
                }
            }
        }.scrollContentBackground(.hidden).background(LabTheme.background).tint(LabTheme.mint)
            .navigationTitle("解析方法・PC").navigationBarTitleDisplayMode(.inline)
            .alert("PCの振動データを削除しますか？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("削除", role: .destructive) {
                    guard let track = deleting, let connection = preferences.connection else { return }
                    Task {
                        do { try await PCAnalysisClient(connection: connection).deleteTrack(track.id); tracks.removeAll { $0.id == track.id } }
                        catch { message = error.localizedDescription }
                        deleting = nil
                    }
                }
                Button("キャンセル", role: .cancel) { deleting = nil }
            }
    }
    private func connect() {
        Task {
            checking = true
            defer { checking = false }
            do {
                let connection = try PCServerConnection(address: preferences.address, token: preferences.token)
                let client = PCAnalysisClient(connection: connection)
                let health = try await client.health()
                tracks = try await client.tracks()
                if health.arrangementAvailable != true {
                    message = "PCへ接続しました。AI解析環境を準備してから曲を作成してください。"
                } else {
                    message = health.youtubeAvailable
                        ? "PCでAI解析・編曲できます。"
                        : "音源ファイルをAI解析できます。YouTube取得ツールをPCで確認してください。"
                }
            } catch { message = error.localizedDescription }
        }
    }
}
