"""An explicit analysis must run even when an identical saved track exists."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch
import wave

import numpy as np

from music_ai import cache_identity
from server import PRIVATE
from signal_analysis import RATE, decode
from test_arrangement import fixture
from worker import run


def write_wave(path, signal, rate, **_):
    with wave.open(str(path), 'wb') as audio:
        audio.setnchannels(2)
        audio.setsampwidth(2)
        audio.setframerate(rate)
        audio.writeframes((np.clip(signal, -1, 1) * 32767).astype('<i2').tobytes())


class ReanalysisTests(unittest.TestCase):
    def setUp(self):
        PRIVATE.mkdir(exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='worker-test-', dir=PRIVATE)).resolve()
        self.folder = self.root / 'working' / 'request'
        self.folder.mkdir(parents=True)
        (self.root / 'tracks').mkdir()

    def tearDown(self):
        assert self.root.parent == PRIVATE.resolve() and self.root.name.startswith('worker-test-')
        shutil.rmtree(self.root)

    def test_arranged_worker_runs_ai_again_and_preserves_old_result_with_independent_score_graph_and_ahap(self):
        signal = .2 * np.sin(np.arange(16 * RATE) * 2 * np.pi * 110 / RATE)
        write_wave(self.folder / 'source', np.column_stack([signal, signal]), RATE)
        pcm, _ = decode(self.folder / 'source', self.folder / 'probe.f32')
        pcm._mmap.close()
        with (self.folder / 'probe.f32').open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        (self.folder / 'probe.f32').unlink()
        graph = fixture()
        graph['audioSHA256'] = digest
        graph['structure']['tempoBPM'] = 120
        identity = cache_identity(digest, 'standard')
        stored = self.root / 'tracks' / (identity + '.json')
        stored.write_text('{"stale":true}', encoding='utf-8')
        (self.folder / 'request.json').write_text(json.dumps(dict(style='arranged', profile='standard', title='regenerate')), encoding='utf-8')
        with patch('music_ai.analyze_music', return_value=graph) as analyze_music, \
             patch.dict('sys.modules', soundfile=SimpleNamespace(write=write_wave)):
            run(self.folder)
        analyze_music.assert_called_once()
        status = json.loads((self.folder / 'status.json').read_text(encoding='utf-8'))
        self.assertEqual(status['state'], 'done', status['message'])
        self.assertNotIn('再利用', status['message'])
        result_id = status['trackID']
        self.assertNotEqual(result_id, identity)
        self.assertEqual(json.loads(stored.read_text(encoding='utf-8')), {'stale': True})
        self.assertEqual(json.loads((self.root / 'tracks' / (result_id + '.json')).read_text(encoding='utf-8'))['version'], 3)
        for suffix in ('.meta.json', '.graph.json', '.score.json'):
            self.assertTrue((self.root / 'tracks' / (result_id + suffix)).is_file())
        self.assertTrue((self.root / 'exports' / result_id / 'manifest.json').is_file())
        self.assertFalse(any(p.name.startswith(('source', 'decoded')) for p in self.folder.iterdir()))

    def test_youtube_reanalysis_fetches_audio_and_preserves_saved_result_when_new_fetch_fails(self):
        video_id = 'gNg2Qw5R-Q4'
        identity = hashlib.sha256(('music-player-pc-v2:following:standard:' + video_id).encode()).hexdigest()
        stored = self.root / 'tracks' / (identity + '.json')
        stored.write_text('{"previous":true}', encoding='utf-8')
        (self.folder / 'request.json').write_text(json.dumps(dict(style='following', profile='standard', videoID=video_id)), encoding='utf-8')
        with patch.dict('sys.modules', yt_dlp=SimpleNamespace(YoutubeDL=Mock(side_effect=ValueError('new download failed')))):
            run(self.folder)
        status = json.loads((self.folder / 'status.json').read_text(encoding='utf-8'))
        self.assertEqual(status['state'], 'failed')
        self.assertEqual(status['message'], 'new download failed')
        self.assertEqual(json.loads(stored.read_text(encoding='utf-8')), {'previous': True})


if __name__ == '__main__':
    unittest.main()
