"""Validate the published contract against real HTTP responses and the example client."""
from contextlib import redirect_stdout
from http.server import ThreadingHTTPServer
import io
import json
from pathlib import Path
import shutil
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from jsonschema import Draft202012Validator
from openapi_spec_validator import validate

from client import APIClient, main as client_main
from server import Companion, Handler, OPENAPI, PRIVATE, ROOT
from unittest.mock import patch


class PublicAPITests(unittest.TestCase):
    def setUp(self):
        PRIVATE.mkdir(exist_ok=True)
        self.root = Path(tempfile.mkdtemp(prefix='api-test-', dir=PRIVATE)).resolve()
        self.companion = Companion(self.root)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.server.companion = self.companion
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        self.client = APIClient(self.url, self.companion.token)
        self.spec = json.loads(OPENAPI.read_text(encoding='utf-8'))

    def tearDown(self):
        for identity, job in self.companion.jobs.items():
            if not job['ended']:
                self.companion.cancel(identity)
            if job['process']:
                job['process'].wait(timeout=15)
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)
        assert self.root.parent == PRIVATE.resolve() and self.root.name.startswith('api-test-')
        shutil.rmtree(self.root)

    def conforms(self, name, value):
        Draft202012Validator({
            '$ref': '#/components/schemas/' + name,
            'components': self.spec['components']}).validate(value)

    def test_openapi_is_valid_and_all_routes_require_the_same_key(self):
        validate(self.spec)
        self.assertEqual(self.client.request('/openapi.json'), self.spec)
        self.conforms('Health', self.client.request('/health'))
        for path, method in [('/health', 'GET'), ('/openapi.json', 'GET'), ('/tracks', 'GET'),
                             ('/tracks/' + 'a' * 64, 'GET'), ('/tracks/' + 'a' * 64, 'DELETE'),
                             ('/tracks/' + 'a' * 64 + '/ahap', 'GET'),
                             ('/jobs', 'POST'), ('/jobs/upload', 'POST'),
                             ('/jobs/unknown', 'GET'), ('/jobs/unknown', 'DELETE'), ('/shutdown', 'POST')]:
            with self.subTest(path=path, method=method):
                request = Request(self.url + path, method=method)
                with self.assertRaises(HTTPError) as failure:
                    urlopen(request, timeout=5)
                self.assertEqual(failure.exception.code, 401)
                self.conforms('Error', json.loads(failure.exception.read()))
        self.assertEqual(self.companion.jobs, {})

    def test_example_streams_demo_and_saved_track_survives_server_state_reset(self):
        job = self.client.analyze_file(ROOT / 'HapticLab/Resources/MusicDemo.wav')
        self.conforms('Job', job)
        track = self.client.wait(job['id'], timeout=40)
        self.conforms('HapticTrack', track)
        self.assertAlmostEqual(track['duration'], 12, places=2)
        identity = track['analysis']['serverTrackID']
        self.assertEqual(self.client.request('/tracks/' + identity), track)
        with self.assertRaisesRegex(RuntimeError, 'HTTP 404'):
            self.client.request('/tracks/' + identity + '/ahap')
        for metadata in self.client.request('/tracks'):
            self.conforms('TrackMetadata', metadata)
        self.server.companion = Companion(self.root, token=self.companion.token)
        self.assertEqual(self.client.request('/tracks/' + identity), track)
        with self.assertRaisesRegex(RuntimeError, 'HTTP 404'):
            self.client.request('/jobs/' + job['id'])
        self.assertEqual(self.client.request('/tracks/' + identity, 'DELETE'), {'deleted': True})
        with self.assertRaisesRegex(RuntimeError, 'HTTP 404'):
            self.client.request('/tracks/' + identity)

    def test_cli_reads_connection_file_and_writes_haptic_json(self):
        connection = self.root / 'connection.json'
        connection.write_text(json.dumps(dict(addresses=[self.url], token=self.companion.token)), encoding='utf-8')
        output = self.root / 'results' / 'demo.json'
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            code = client_main(['--connection', str(connection), 'analyze', '--file',
                                str(ROOT / 'HapticLab/Resources/MusicDemo.wav'), '--style', 'following', '--output', str(output)])
        self.assertEqual(code, 0)
        self.conforms('HapticTrack', json.loads(output.read_text(encoding='utf-8')))
        self.assertNotIn(self.companion.token, stdout.getvalue())

    def test_invalid_saved_ids_cannot_read_outside_the_cache(self):
        for identity in ['invalid', '..', 'z' * 64]:
            with self.subTest(identity=identity):
                with self.assertRaisesRegex(RuntimeError, 'HTTP 400'):
                    self.client.request('/tracks/' + identity)
        with self.assertRaisesRegex(RuntimeError, 'HTTP 404'):
            self.client.request('/tracks/' + 'a' * 64)
        with self.assertRaises(ValueError):
            APIClient('http://example.com:8765', self.companion.token)

    def test_arrangement_request_without_runtime_fails_before_queueing_instead_of_dsp_fallback(self):
        with patch('server.arrangement_available', return_value=False):
            self.assertFalse(self.client.request('/health')['arrangementAvailable'])
            with self.assertRaisesRegex(RuntimeError, 'HTTP 400'):
                self.client.analyze_video('gNg2Qw5R-Q4', 'arranged')
        self.assertFalse(self.companion.jobs)

    def test_ahap_export_client_rejects_server_supplied_paths_before_writing(self):
        destination = self.root / 'export-test'
        with patch.object(self.client, 'request', return_value={'manifest':{},'files':{'../outside.ahap':{}}}):
            with self.assertRaises(ValueError):
                self.client.export_ahap('a'*64, destination)
        self.assertFalse(destination.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
