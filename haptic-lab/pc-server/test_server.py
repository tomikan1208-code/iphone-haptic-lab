"""Exercise real decoding, worker persistence, cancellation, and the phone's HTTP protocol."""
import base64
import hashlib
import io
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import tempfile
import threading
import time
import unittest
import wave
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import numpy as np

from server import Companion, Handler, PRIVATE, ROOT
from signal_analysis import analyze, compose, decode, estimate_beats, orchestral, RATE, BAND_EDGES


def wait_until(predicate, timeout=40):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        result = predicate()
        if result:
            return result
        time.sleep(.05)
    raise AssertionError('PC job did not finish in time')


class PCServerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        PRIVATE.mkdir(exist_ok=True)
        cls.metrics = {}

    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix='test-', dir=PRIVATE)).resolve()
        self.companion = Companion(self.root)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.server.companion = self.companion
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = 'http://127.0.0.1:' + str(self.server.server_port)

    def tearDown(self):
        for identity, job in list(self.companion.jobs.items()):
            if not job['ended']:
                self.companion.cancel(identity)
            if job['process']:
                job['process'].wait(timeout=15)
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        # All test data belongs to this workspace directory; never remove a computed external path.
        assert self.root.parent == PRIVATE.resolve() and self.root.name.startswith('test-')
        shutil.rmtree(self.root)

    @classmethod
    def tearDownClass(cls):
        (ROOT / '.build').mkdir(exist_ok=True)
        (ROOT / '.build' / 'pc-test-metrics.json').write_text(json.dumps(cls.metrics, indent=2), encoding='utf-8')

    def api(self, path, method='GET', body=None, headers=None, authenticated=True):
        supplied = dict(headers or {})
        if authenticated:
            supplied['Authorization'] = 'Bearer ' + self.companion.token
        request = Request(self.url + path, data=body, method=method, headers=supplied)
        with urlopen(request, timeout=15) as response:
            return json.loads(response.read())

    def upload(self, audio, style='following', profile='standard'):
        return self.api('/jobs/upload', 'POST', audio, {
            'Content-Type': 'application/octet-stream',
            'X-Media-Title': base64.b64encode('テスト音源'.encode()).decode(),
            'X-Generation-Style': style, 'X-Music-Profile': profile})['id']

    def done(self, identity):
        status = wait_until(lambda: self.api('/jobs/' + identity) if self.companion.jobs[identity]['ended'] else None)
        self.assertEqual(status['state'], 'done', status.get('message'))
        return status

    def test_requires_authentication_and_rejects_malformed_requests_without_creating_jobs(self):
        with self.assertRaises(HTTPError) as failure:
            self.api('/health', authenticated=False)
        self.assertEqual(failure.exception.code, 401)
        self.assertEqual(self.api('/health')['protocolVersion'], 1)
        for value in [[], {}, {'videoID': '../bad'}, {'videoID': 123}, {'videoID': 'BaW_jenozKc', 'style': 'ai'}]:
            with self.assertRaises(HTTPError) as failure:
                self.api('/jobs', 'POST', json.dumps(value).encode(), {'Content-Type': 'application/json'})
            self.assertEqual(failure.exception.code, 400)
        self.assertEqual(len(self.companion.jobs), 0)
        self.assertEqual(list(self.companion.working.iterdir()), [])
        with self.assertRaises(HTTPError) as failure:
            self.api('/jobs/upload', 'POST', b'')
        self.assertEqual(failure.exception.code, 400)

    def test_upload_reanalyzes_real_demo_then_persists_and_deletes_one_track(self):
        audio = (ROOT / 'HapticLab' / 'Resources' / 'MusicDemo.wav').read_bytes()
        first = self.done(self.upload(audio))
        track = first['track']
        self.assertAlmostEqual(track['duration'], 12, places=2)
        self.assertEqual(track['audioSHA256'], hashlib.sha256(audio).hexdigest())
        self.assertEqual(track['analysis']['engine'], 'pc')
        self.assertEqual(track['analysis']['hopMilliseconds'], 10)
        self.assertEqual(track['version'], 2)
        self.assertEqual(len(track['spectrum'][0]['levels']), 24)
        self.assertEqual(track['spectrum'][0]['time'], 0)
        self.assertEqual(track['spectrum'][-1]['time'], track['duration'])
        self.assertGreater(len(track['envelope']), 1200)
        self.assertGreater(len(track['taps']), 10)
        self.assertTrue(all(0 <= point['energy'] <= 1 and 0 <= point['bass'] <= 1 for point in track['envelope']))
        self.metrics['demo12SecondsAnalysis'] = track['analysis']['elapsedSeconds']
        previous_created = self.api('/tracks')[0]['createdAt']
        # An identifiable saved result must not be returned by an explicit new analysis.
        stored = self.companion.tracks / (first['trackID'] + '.json')
        stale = json.loads(stored.read_text(encoding='utf-8'))
        stale['analysis']['elapsedSeconds'] = -123
        stored.write_text(json.dumps(stale), encoding='utf-8')
        repeated = self.done(self.upload(audio))
        self.assertNotEqual(first['trackID'], repeated['trackID'])
        self.assertGreater(repeated['track']['analysis']['elapsedSeconds'], 0)
        self.assertNotIn('再利用', repeated['message'])
        self.assertGreater(self.api('/tracks')[0]['createdAt'], previous_created)
        restored = Companion(self.root)
        self.assertEqual(len(restored.stored_tracks()), 2)
        arranged = self.done(self.upload(audio, profile='orchestral'))
        self.assertNotEqual(first['trackID'], arranged['trackID'])
        self.assertEqual(arranged['track']['analysis']['profile'], 'orchestral')
        self.assertEqual(len(self.api('/tracks')), 3)
        self.api('/tracks/' + first['trackID'], 'DELETE')
        remaining = self.api('/tracks')
        self.assertEqual([item['id'] for item in remaining], [arranged['trackID'], repeated['trackID']])
        self.assertFalse((self.companion.tracks / (first['trackID'] + '.json')).exists())
        self.assertTrue((self.companion.tracks / (arranged['trackID'] + '.json')).exists())
        for job in self.companion.jobs.values():
            self.assertFalse(any(path.name.startswith(('source', 'decoded')) for path in job['folder'].iterdir()))

    def test_failed_decode_removes_temporary_audio_and_does_not_publish_a_track(self):
        identity = self.upload(b'not audio')
        wait_until(lambda: self.companion.jobs[identity]['ended'])
        self.assertEqual(self.api('/jobs/' + identity)['state'], 'failed')
        self.assertEqual(self.api('/tracks'), [])
        self.assertFalse((self.companion.jobs[identity]['folder'] / 'source').exists())
        self.assertFalse((self.companion.jobs[identity]['folder'] / 'decoded.f32').exists())

    def test_exited_worker_cannot_leave_phone_polling_stale_running_progress(self):
        identity = self.companion.create_job('Stopped worker', 'following')
        job = self.companion.jobs[identity]
        (job['folder'] / 'status.json').write_text(json.dumps(dict(state='running', progress=.4, message='old')),
                                                 encoding='utf-8')
        job['ended'] = True
        status = self.api('/jobs/' + identity)
        self.assertEqual(status['state'], 'failed')
        self.assertEqual(status['progress'], 0)

    def test_atomic_status_write_retries_transient_windows_reader_locks(self):
        from worker import atomic_json
        from unittest.mock import patch
        replace = Path.replace
        calls = []
        def reader_lock(source, destination):
            calls.append(source)
            if len(calls) < 3: raise PermissionError('temporary Windows read handle')
            return replace(source, destination)
        destination = self.root / 'progress.json'
        destination.write_text('{"old":true}', encoding='utf-8')
        with patch.object(Path, 'replace', reader_lock):
            atomic_json(destination, dict(state='running', progress=.7))
        self.assertEqual(json.loads(destination.read_text(encoding='utf-8')), dict(state='running', progress=.7))
        self.assertFalse(destination.with_suffix('.tmp').exists())

    def test_saved_spectrum_locates_audio_tones_and_preserves_silent_sections(self):
        for frequency in (80, 300, 3000):
            with self.subTest(frequency=frequency):
                pcm = np.zeros((2 * RATE, 2), dtype=np.float32)
                tone = .4 * np.sin(np.arange(RATE) * 2 * np.pi * frequency / RATE)
                pcm[:RATE, 0] = tone
                pcm[:RATE, 1] = -tone
                track = analyze(pcm, 2, 'a' * 64, lambda *_: None, lambda: False)
                levels = track['spectrum'][50]['levels']
                expected = np.searchsorted(BAND_EDGES, frequency, side='right') - 1
                self.assertLessEqual(abs(int(np.argmax(levels)) - expected), 1)
                self.assertGreater(max(levels), .9)
                self.assertEqual(max(track['spectrum'][150]['levels']), 0)
                self.assertEqual(track['envelope'][150]['mid'], 0)
                self.assertEqual(track['envelope'][150]['high'], 0)
                arranged = orchestral(json.loads(json.dumps(track)))
                self.assertEqual(arranged['spectrum'], track['spectrum'])

    def test_queued_cancellation_removes_audio_and_leaves_no_saved_track(self):
        self.companion.worker_slot.acquire()
        try:
            identity = self.upload(b'job-owned temporary audio')
            self.api('/jobs/' + identity, 'DELETE')
            self.assertEqual(self.api('/jobs/' + identity)['state'], 'canceled')
            self.assertFalse((self.companion.jobs[identity]['folder'] / 'source').exists())
            self.assertEqual(self.api('/tracks'), [])
        finally:
            self.companion.worker_slot.release()

    def test_shutdown_requires_key_and_closes_the_service(self):
        with self.assertRaises(HTTPError) as failure:
            self.api('/shutdown', 'POST', authenticated=False)
        self.assertEqual(failure.exception.code, 401)
        self.assertEqual(self.api('/shutdown', 'POST'), {'stopping': True})
        self.thread.join(timeout=5)
        self.assertFalse(self.thread.is_alive())

    def test_running_cancellation_closes_decoder_and_removes_temporary_audio(self):
        buffer = io.BytesIO()
        samples = (.2 * np.sin(np.arange(22050 * 60) * (2 * np.pi * 110 / 22050)) * 32767).astype('<i2')
        with wave.open(buffer, 'wb') as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(22050)
            audio.writeframes(samples.tobytes())
        identity = self.upload(buffer.getvalue())
        folder = self.companion.jobs[identity]['folder']
        wait_until(lambda: (folder / 'decoded.f32').exists())
        self.api('/jobs/' + identity, 'DELETE')
        wait_until(lambda: self.companion.jobs[identity]['ended'])
        self.assertEqual(self.api('/jobs/' + identity)['state'], 'canceled')
        self.assertFalse(any(path.name.startswith(('source', 'decoded')) for path in folder.iterdir()))
        self.assertEqual(self.api('/tracks'), [])

    def test_stereo_antiphase_retains_bass_and_bad_samples_are_rejected(self):
        times = np.arange(RATE * 2) / RATE
        left = (.25 * np.sin(times * 2 * np.pi * 110)).astype(np.float32)
        same = np.column_stack([left, left])
        opposite = np.column_stack([left, -left])
        first = analyze(same, 2, 'a' * 64, lambda *_: None, lambda: False)
        second = analyze(opposite, 2, 'b' * 64, lambda *_: None, lambda: False)
        self.assertGreater(max(point['bass'] for point in second['envelope']), .9)
        np.testing.assert_allclose([point['bass'] for point in first['envelope']], [point['bass'] for point in second['envelope']])
        with self.assertRaises(ValueError):
            analyze(np.zeros((RATE, 2), np.float32), 1, 'a' * 64, lambda *_: None, lambda: False)
        same[10, 0] = np.nan
        with self.assertRaises(ValueError):
            analyze(same, 2, 'a' * 64, lambda *_: None, lambda: False)

    def test_orchestral_profile_keeps_crescendo_natural_onsets_and_silence(self):
        track = dict(duration=4, envelope=[dict(time=i*.01, bass=i/300 if i < 300 else 0,
            energy=i/300 if i < 300 else 0, sharpness=.8) for i in range(401)],
            taps=[dict(time=t, intensity=v, sharpness=.8) for t, v in [(.31,.9),(.54,.8),(1.37,.85),(1.6,.2)]])
        arranged = orchestral(track)
        self.assertEqual([tap['time'] for tap in arranged['taps']], [.31, 1.37])
        self.assertGreater(arranged['envelope'][280]['energy'], arranged['envelope'][100]['energy'] * 2)
        self.assertEqual(arranged['envelope'][350]['energy'], 0)
        self.assertTrue(all(tap['intensity'] <= .4 and tap['sharpness'] <= .35 for tap in arranged['taps']))

    def test_musical_composition_leaves_silent_rests(self):
        track = dict(duration=4, envelope=[dict(time=i*.01, bass=.8 if i < 200 else 0,
            energy=.8 if i < 200 else 0, sharpness=.5) for i in range(401)],
            taps=[dict(time=i*.5, intensity=.8, sharpness=.5) for i in range(1,8)])
        beats, downbeats, bpm = estimate_beats(track)
        self.assertAlmostEqual(bpm, 120, delta=1)
        arranged = compose(track, beats, downbeats)
        self.assertTrue(arranged['taps'])
        self.assertTrue(all(tap['time'] < 2 for tap in arranged['taps']))
        self.assertEqual(arranged['envelope'][300]['energy'], 0)

    def test_three_minute_analysis_stays_bounded_and_can_be_canceled(self):
        # A varied three-minute signal is a repeatable throughput measurement, not a real-device estimate.
        times = np.arange(RATE * 180, dtype=np.float32) / RATE
        wave = .15 * np.sin(times * (2 * np.pi * 110)) * (.3 + .7 * np.sin(times * .4) ** 2)
        wave += .05 * np.sin(times * (2 * np.pi * 330))
        signal = np.column_stack([wave, -wave])
        started = time.monotonic()
        track = analyze(signal, 180, 'a' * 64, lambda *_: None, lambda: False)
        self.metrics['synthetic180SecondsAnalysis'] = time.monotonic() - started
        self.assertEqual(len(track['envelope']), 18001)
        self.assertTrue(all(0 <= point['energy'] <= 1 for point in track['envelope']))
        with self.assertRaises(InterruptedError):
            analyze(signal, 180, 'a' * 64, lambda *_: None, lambda: True)


if __name__ == '__main__':
    unittest.main(verbosity=2)
