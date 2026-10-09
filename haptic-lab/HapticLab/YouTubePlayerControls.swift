import Foundation
import WebKit

enum YouTubePlayerControls {
    /// The iframe keeps controls=1 for its entire lifetime. A stylesheet in an
    /// isolated WebKit world hides its chrome in portrait without reloading it.
    static func frameScript(origin: String) -> String {
        let encoded = (try? JSONEncoder().encode(origin)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return """
        (() => {
          if (location.protocol !== 'https:' ||
              !(location.hostname === 'youtube.com' || location.hostname.endsWith('.youtube.com')) ||
              !location.pathname.startsWith('/embed/')) return;
          const trustedOrigin = \(encoded);
          const style = document.createElement('style');
          style.textContent = `html[data-reson-hide-controls] .ytp-chrome-top,
            html[data-reson-hide-controls] .ytp-chrome-bottom,
            html[data-reson-hide-controls] .ytp-gradient-top,
            html[data-reson-hide-controls] .ytp-gradient-bottom,
            html[data-reson-hide-controls] .ytp-pause-overlay,
            html[data-reson-hide-controls] .ytp-large-play-button,
            html[data-reson-hide-controls] .ytp-cards-button,
            html[data-reson-hide-controls] .ytp-settings-menu,
            html[data-reson-hide-controls] .ytp-tooltip {
              visibility: hidden !important; pointer-events: none !important;
            }`;
          (document.head || document.documentElement).appendChild(style);
          document.documentElement.setAttribute('data-reson-hide-controls', '');
          window.addEventListener('message', event => {
            if (event.source !== window.parent || event.origin !== trustedOrigin ||
                !event.data || event.data.type !== 'reson-player-controls' ||
                typeof event.data.visible !== 'boolean') return;
            document.documentElement.toggleAttribute('data-reson-hide-controls', !event.data.visible);
          });
          window.parent.postMessage({type: 'reson-player-controls-ready'}, trustedOrigin);
        })();
        """
    }

    static func script(origin: String) -> WKUserScript {
        WKUserScript(source: frameScript(origin: origin), injectionTime: .atDocumentEnd,
                     forMainFrameOnly: false, in: .world(name: "ResonPlayerChrome"))
    }
}
