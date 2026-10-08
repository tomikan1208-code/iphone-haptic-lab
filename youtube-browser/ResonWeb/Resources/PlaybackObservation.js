(() => {
  'use strict';
  const fixture = __RESON_TEST_FIXTURE__;
  const pageURL = () => fixture ? document.baseURI : location.href;
  const allowed = url => url.protocol === 'https:' && !url.username && !url.password &&
    (url.hostname === 'youtube.com' || url.hostname.endsWith('.youtube.com'));
  try { if (!allowed(new URL(pageURL()))) return; } catch (_) { return; }
  if (window.__resonObservationInstalled) return;
  window.__resonObservationInstalled = true;

  const validID = value => /^[A-Za-z0-9_-]{11}$/.test(value || '') ? value : '';
  const videoID = url => url.pathname === '/watch' ? validID(url.searchParams.get('v')) :
    /^\/(shorts|live)\//.test(url.pathname) ? validID(url.pathname.split('/')[2]) : '';
  const listened = new WeakSet();
  const loadedFor = new WeakMap();
  let previousID = null, videoBeforeSwitch = null, sourceBeforeSwitch = '';
  let currentVideo = null, waiting = false;

  function listen(video) {
    if (!video || listened.has(video)) return;
    listened.add(video);
    for (const event of ['loadedmetadata', 'loadeddata', 'playing', 'play', 'pause', 'seeking',
                         'seeked', 'waiting', 'stalled', 'ended', 'ratechange', 'emptied']) {
      video.addEventListener(event, () => {
        if (event === 'loadedmetadata' || event === 'loadeddata') {
          loadedFor.set(video, videoID(new URL(pageURL())));
        }
        if (event === 'waiting' || event === 'stalled' || event === 'emptied') waiting = true;
        if (event === 'playing' || event === 'loadeddata' || event === 'seeked') waiting = false;
        sample();
      });
    }
  }

  function sample() {
    try {
      const url = new URL(pageURL());
      if (!allowed(url)) return;
      const id = videoID(url);
      const video = document.querySelector('#movie_player video, .html5-video-player video, video.html5-main-video, ytm-player video, video');
      if (id !== previousID) {
        videoBeforeSwitch = previousID === null ? null : currentVideo;
        sourceBeforeSwitch = videoBeforeSwitch?.currentSrc || '';
        previousID = id;
        waiting = false;
      }
      if (video !== currentVideo) waiting = false;
      currentVideo = video;
      listen(video);
      const owner = video?.closest('ytd-watch-flexy[video-id], ytm-watch[video-id]');
      const ownerID = owner?.getAttribute('video-id') || '';
      // A SPA URL can change before its old media element has been replaced.
      const identityReady = Boolean(id && video && (!ownerID || ownerID === id) &&
        (!videoBeforeSwitch || video !== videoBeforeSwitch || loadedFor.get(video) === id ||
         (video.currentSrc && video.currentSrc !== sourceBeforeSwitch)));
      const duration = Number.isFinite(video?.duration) && video.duration > 0 ? video.duration : 0;
      const title = (document.querySelector('meta[property="og:title"]')?.content ||
        document.querySelector('h1.ytd-watch-metadata, h1.ytm-slim-video-metadata-renderer')?.textContent ||
        document.title.replace(/\s*[-–]\s*YouTube\s*$/, '') || 'YouTube動画').trim().slice(0, 240);
      const artist = (document.querySelector('#owner #channel-name a, ytm-slim-owner-renderer .yt-core-attributed-string')?.textContent || '').trim().slice(0, 160);
      window.webkit.messageHandlers.resonPlayback.postMessage({
        url: url.href, videoID: id, title, artist, sent: Date.now(),
        position: Number.isFinite(video?.currentTime) ? video.currentTime : 0,
        duration, rate: Number.isFinite(video?.playbackRate) ? video.playbackRate : 1,
        paused: !video || video.paused, ended: !video || video.ended,
        seeking: Boolean(video?.seeking), ready: identityReady && duration > 0,
        buffering: !video || video.readyState < 3 || waiting,
        advertisement: Boolean(document.querySelector('.ad-showing, .ad-interrupting')),
        hidden: document.visibilityState === 'hidden'
      });
    } catch (_) { /* Page transitions may temporarily detach the video element. */ }
  }

  function tick() {
    sample();
    setTimeout(tick, document.visibilityState === 'hidden' ? 250 : 20);
  }
  document.addEventListener('visibilitychange', sample);
  document.addEventListener('yt-navigate-finish', sample);
  tick();
})();
