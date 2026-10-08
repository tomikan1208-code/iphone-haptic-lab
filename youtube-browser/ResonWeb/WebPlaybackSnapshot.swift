import Foundation
import CoreFoundation

struct WebPlaybackSnapshot: Equatable {
    let url: URL
    let videoID: String?
    let title: String
    let artist: String
    let position: Double
    let duration: Double
    let rate: Double
    let sent: Double
    let paused: Bool
    let ended: Bool
    let seeking: Bool
    let ready: Bool
    let buffering: Bool
    let advertisement: Bool
    let hidden: Bool

    var playing: Bool { ready && !paused && !ended && !seeking && !buffering && !advertisement && !hidden }
    var selection: MusicSelection? {
        guard let videoID, var selection = try? MusicSelection.youtube(id: videoID, title: title, artist: artist) else { return nil }
        if ready && !advertisement && duration > 0 { selection.duration = duration }
        return selection
    }

    static func acceptsOrigin(scheme: String, host: String, mainFrame: Bool) -> Bool {
        guard mainFrame, scheme == "https" else { return false }
        let host = host.lowercased()
        return host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    static func decode(_ body: Any, pageURL: URL, now: Double = Date().timeIntervalSince1970) -> Self? {
        guard let values = body as? [String: Any], let text = values["url"] as? String,
              let url = URL(string: text), BrowserNavigation.isYouTube(url),
              url.host?.lowercased() == pageURL.host?.lowercased(), pageURL.scheme == "https" else { return nil }
        func number(_ key: String) -> Double? {
            guard let value = values[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                  value.doubleValue.isFinite else { return nil }
            return value.doubleValue
        }
        func flag(_ key: String) -> Bool? {
            guard let value = values[key] as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
            return value.boolValue
        }
        guard let position = number("position"), position >= 0,
              let duration = number("duration"), duration >= 0,
              let rate = number("rate"), (0.25...2).contains(rate),
              let sent = number("sent"), (-0.1...0.35).contains(now - sent / 1_000),
              let paused = flag("paused"), let ended = flag("ended"), let seeking = flag("seeking"),
              let ready = flag("ready"), let buffering = flag("buffering"),
              let advertisement = flag("advertisement"), let hidden = flag("hidden"),
              let rawID = values["videoID"] as? String else { return nil }
        let expectedID = try? MusicSelection.parse(pageURL.absoluteString).videoID
        let urlID = try? MusicSelection.parse(url.absoluteString).videoID
        let id = rawID.isEmpty ? nil : rawID
        guard id == expectedID, id == urlID, id.map(MusicSelection.validVideoID) ?? true,
              !ready || (id != nil && duration > 0 && position <= duration + 1) else { return nil }
        return Self(url: url, videoID: id, title: String((values["title"] as? String ?? "YouTube動画").prefix(240)),
                    artist: String((values["artist"] as? String ?? "").prefix(160)), position: position,
                    duration: duration, rate: rate, sent: sent, paused: paused, ended: ended, seeking: seeking,
                    ready: ready, buffering: buffering, advertisement: advertisement, hidden: hidden)
    }
}
