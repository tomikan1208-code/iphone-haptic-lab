import Foundation
import YouTubeKit

enum YouTubeMedia {
    static func audioURL(for selection: MusicSelection) async throws -> URL {
        guard let id = selection.videoID, MusicSelection.validVideoID(id) else { throw MusicError.invalidURL }
        if let duration = selection.duration, duration > MusicHapticTrack.maximumDuration { throw MusicError.tooLong }
        try Task.checkCancellation()
        do {
            // Extraction runs on the phone; never send the video to a third-party fallback server.
            let streams = try await YouTube(videoID: id, methods: [.local]).streams
            try Task.checkCancellation()
            guard let stream = streams.filterAudioOnly()
                .filter({ $0.fileExtension == .m4a && $0.isNativelyPlayable }).highestAudioBitrateStream(),
                  stream.url.scheme == "https", let host = stream.url.host?.lowercased(),
                  host == "googlevideo.com" || host.hasSuffix(".googlevideo.com") else {
                throw MusicError.network("この動画の解析用音声を取得できませんでした。別の動画か、同じ音源のファイルで試してください。")
            }
            return stream.url
        } catch {
            try Task.checkCancellation()
            throw MusicError.network("YouTubeの音声を取得できませんでした。動画の公開状態・地域制限を確認し、再試行してください。")
        }
    }
}

