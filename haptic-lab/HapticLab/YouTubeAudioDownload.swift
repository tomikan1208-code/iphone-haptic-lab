import Foundation

struct MusicDownloadRange: Equatable, Sendable {
    let start: Int64
    let end: Int64
    let total: Int64
    var count: Int64 { end - start + 1 }

    func request(for url: URL) throws -> URLRequest {
        guard start >= 0, end >= start, end < total, total <= MusicAnalyzer.maximumBytes,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw MusicError.invalidURL }
        // Use absolute HTTP ranges on the original resource, preserving signed query bytes.
        // A URL range combined with this header would apply the range twice.
        var items = (components.percentEncodedQuery ?? "").split(separator: "&").map(String.init)
        items.removeAll { $0.hasPrefix("range=") }
        components.percentEncodedQuery = items.joined(separator: "&")
        guard let target = components.url else { throw MusicError.invalidURL }
        var request = URLRequest(url: target)
        request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    func validate(_ response: HTTPURLResponse) throws {
        guard [200, 206].contains(response.statusCode), response.url.map(YouTubeAudioDownload.isYouTubeAudio) == true,
              response.mimeType?.lowercased().contains("text/") != true else {
            throw MusicError.network("音声を取得できませんでした（\(response.statusCode)）。再試行してください。")
        }
        if let value = response.value(forHTTPHeaderField: "Content-Range") {
            guard value == "bytes \(start)-\(end)/\(total)" else {
                throw MusicError.network("音声の取得範囲が一致しませんでした。再試行してください。")
            }
        } else if response.statusCode == 206 {
            throw MusicError.network("音声の取得範囲を確認できませんでした。")
        }
        if response.statusCode == 200, start != 0 || count != total {
            throw MusicError.network("音声の分割取得に対応しない応答でした。再試行してください。")
        }
        // Reject servers that ignore the requested range before accepting the body.
        let length = response.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init) ?? response.expectedContentLength
        guard length < 0 || length == count else {
            throw MusicError.network("音声の分割取得に対応しない応答でした。別の動画で試してください。")
        }
    }
}

enum YouTubeAudioDownload {
    static let chunkBytes: Int64 = 1_024 * 1_024
    typealias Fetch = @Sendable (URLRequest, MusicDownloadRange, @escaping @Sendable (Int64) -> Void) async throws -> Data

    static func isYouTubeAudio(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
    }

    static func download(_ url: URL, to destination: URL, progress: @escaping MusicPreparationServices.Progress,
                         fetch: @escaping Fetch = { request, range, received in
                             try await MusicDownloadChunk(range: range, received: received).download(request)
                         }) async throws -> URL {
        guard isYouTubeAudio(url), let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "clen" })?.value,
              let total = Int64(value), total > 0, total <= MusicAnalyzer.maximumBytes else {
            throw MusicError.network("音声の容量を確認できませんでした。別の動画で試してください。")
        }
        try Task.checkCancellation()
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw MusicError.storage("解析用の音声を保存できませんでした。")
        }
        let file = try FileHandle(forWritingTo: destination)
        var complete = false
        defer {
            try? file.close()
            if !complete { try? FileManager.default.removeItem(at: destination) }
        }
        let started = Date()
        var offset: Int64 = 0
        while offset < total {
            try Task.checkCancellation()
            let range = MusicDownloadRange(start: offset, end: min(total - 1, offset + chunkBytes - 1), total: total)
            let request = try range.request(for: url)
            let committed = offset
            let report: @Sendable (Int64) -> Void = { received in
                let bytes = min(total, committed + received)
                let speed = Double(bytes) / max(0.1, Date().timeIntervalSince(started))
                let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                let all = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                let rate = ByteCountFormatter.string(fromByteCount: Int64(speed), countStyle: .file)
                let remaining = Int(ceil(Double(total - bytes) / max(1, speed)))
                let percent = Int(Double(bytes) / Double(total) * 100)
                progress(0.02 + Double(bytes) / Double(total) * 0.06,
                         "音声をダウンロード中 \(percent)% · \(size) / \(all) · \(rate)/s · 残り約\(remaining)秒")
            }
            let data = try await fetch(request, range, report)
            try Task.checkCancellation()
            guard Int64(data.count) == range.count else {
                throw MusicError.network("音声が途中で途切れました。再試行してください。")
            }
            try file.write(contentsOf: data)
            offset += Int64(data.count)
            report(range.count)
        }
        try file.synchronize()
        try Task.checkCancellation()
        complete = true
        return destination
    }
}

private final class MusicDownloadChunk: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let range: MusicDownloadRange
    private let received: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var finished = false
    private var lastReport = Date.distantPast

    init(range: MusicDownloadRange, received: @escaping @Sendable (Int64) -> Void) {
        self.range = range
        self.received = received
    }

    func download(_ request: URLRequest) async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !finished else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                let configuration = URLSessionConfiguration.ephemeral
                configuration.urlCache = nil
                configuration.timeoutIntervalForRequest = 30
                configuration.timeoutIntervalForResource = 90
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.dataTask(with: request)
                self.task = task
                lock.unlock()
                task.resume()
            }
        }, onCancel: { self.finish(.failure(CancellationError())) })
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let response = response as? HTTPURLResponse else { throw MusicError.network("音声の応答がありませんでした。") }
            try range.validate(response)
            completionHandler(.allow)
        } catch { completionHandler(.cancel); finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        guard Int64(buffer.count) + Int64(data.count) <= range.count else {
            lock.unlock(); finish(.failure(MusicError.network("音声の取得範囲を超えた応答でした。"))); return
        }
        buffer.append(data)
        let count = Int64(buffer.count)
        let report = Date().timeIntervalSince(lastReport) >= 0.2 || count == range.count
        if report { lastReport = Date() }
        lock.unlock()
        if report { received(count) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else {
            lock.lock()
            let data = buffer
            lock.unlock()
            finish(.success(data))
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation, session = self.session, task = self.task
        self.continuation = nil; self.session = nil; self.task = nil
        lock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }
}
