import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';

const script = fs.readFileSync(new URL('../ResonWeb/Resources/PlaybackObservation.js', import.meta.url), 'utf8')
  .replace('__RESON_TEST_FIXTURE__', 'false');
const first = 'https://www.youtube.com/watch?v=lkiV3U0GfGg';
function harness(url = first) {
  const messages = [], timers = [], listeners = new Map();
  const video = { currentTime: 10, duration: 60, playbackRate: 1, paused: false, ended: false,
    seeking: false, readyState: 4, currentSrc: 'blob:original-media',
    addEventListener(event, callback) { listeners.set(event, callback); }, closest() { return null; },
    play() { throw new Error('The observer must not control playback'); },
    pause() { throw new Error('The observer must not control playback'); } };
  const state = { ad: false, video };
  const document = { title: 'Piano - YouTube', visibilityState: 'visible', baseURI: url,
    querySelector(selector) {
      if (selector.startsWith('#movie_player')) return state.video;
      if (selector.startsWith('.ad-showing')) return state.ad ? {} : null;
      return null;
    }, addEventListener() {} };
  const location = { href: url };
  const window = { webkit: { messageHandlers: { resonPlayback: { postMessage(value) { messages.push(value); } } } } };
  vm.runInNewContext(script, { window, document, location, URL, WeakMap, WeakSet, Date,
    setTimeout(callback) { timers.push(callback); } });
  return { messages, timers, listeners, video, state, document, location,
    tick() { const callback = timers.shift(); assert.ok(callback); callback(); return messages.at(-1); } };
}

test('reads the HTML media clock, rate and pause without changing site playback', () => {
  const h = harness();
  assert.equal(h.messages[0].videoID, 'lkiV3U0GfGg');
  assert.equal(h.messages[0].position, 10);
  assert.equal(h.messages[0].ready, true);
  assert.equal(h.messages[0].title, 'Piano');
  h.video.currentTime = 24;
  h.video.playbackRate = 1.5;
  assert.equal(h.tick().position, 24);
  assert.equal(h.messages.at(-1).rate, 1.5);
  h.video.paused = true;
  assert.equal(h.tick().paused, true);
});
test('ads, seeking, stalling and visibility are reported immediately', () => {
  const h = harness();
  h.state.ad = true;
  assert.equal(h.tick().advertisement, true);
  h.state.ad = false;
  h.video.seeking = true;
  h.listeners.get('seeking')();
  assert.equal(h.messages.at(-1).seeking, true);
  h.video.seeking = false;
  h.listeners.get('waiting')();
  assert.equal(h.messages.at(-1).buffering, true);
  h.listeners.get('playing')();
  assert.equal(h.messages.at(-1).buffering, false);
  h.document.visibilityState = 'hidden';
  assert.equal(h.tick().hidden, true);
});
test('SPA navigation silences the old element until the new media is loaded', () => {
  const h = harness();
  h.location.href = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
  assert.equal(h.tick().ready, false);
  assert.equal(h.messages.at(-1).videoID, 'dQw4w9WgXcQ');
  assert.equal(h.tick().ready, false);
  h.listeners.get('loadedmetadata')();
  assert.equal(h.messages.at(-1).ready, true);
});
test('a replaced media element or source can resume a new video', () => {
  const h = harness();
  h.location.href = 'https://www.youtube.com/watch?v=dQw4w9WgXcQ';
  assert.equal(h.tick().ready, false);
  h.video.currentSrc = 'blob:new-media';
  assert.equal(h.tick().ready, true);
});
test('feed previews and live or non-finite duration cannot become ready tracks', () => {
  const h = harness('https://www.youtube.com/feed/history');
  assert.equal(h.messages[0].videoID, '');
  assert.equal(h.messages[0].ready, false);
  h.location.href = first;
  h.video.duration = Infinity;
  assert.equal(h.tick().duration, 0);
  assert.equal(h.messages.at(-1).ready, false);
});
test('authentication, external, lookalike and HTTP pages do not install an observer', () => {
  for (const url of ['https://accounts.google.com/', 'https://www.google.com/',
    'https://youtube.com.evil.org/', 'http://www.youtube.com/', 'https://user:pass@www.youtube.com/']) {
    const h = harness(url);
    assert.equal(h.messages.length, 0, url);
    assert.equal(h.timers.length, 0, url);
    assert.equal(h.listeners.size, 0, url);
  }
});
