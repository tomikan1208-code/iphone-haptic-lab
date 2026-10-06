"""Dependency-free example client for the Reson LAN API (Python 3.11+)."""
import argparse
import base64
import ipaddress
import json
import os
from pathlib import Path
import re
import sys
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

ROOT = Path(__file__).resolve().parent.parent
MAX_BYTES = 512 * 1024 * 1024


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *_):
        # Match the iPhone client: do not forward the connection key to redirects.
        return None


class APIClient:
    def __init__(self, url, token, timeout=120):
        parts = urlsplit(url)
        if (parts.scheme not in ('http', 'https') or not parts.hostname
                or parts.username or parts.password or parts.query or parts.fragment
                or parts.path not in ('', '/') or not re.fullmatch(r'[A-Za-z0-9_-]{24,}', token)):
            raise ValueError('サーバーURLと接続キーを確認してください。')
        if parts.scheme == 'http':
            try:
                address = ipaddress.ip_address(parts.hostname)
                local = address.is_private or address.is_loopback
            except ValueError:
                local = parts.hostname == 'localhost' or parts.hostname.endswith('.local')
            if not local:
                raise ValueError('HTTP接続はローカルネットワークだけに利用できます。')
        self.url = url.rstrip('/')
        self.token = token
        self.timeout = timeout
        self.opener = build_opener(NoRedirect())

    def request(self, path, method='GET', body=None, headers=None):
        supplied = dict(headers or {})
        supplied['Authorization'] = 'Bearer ' + self.token
        request = Request(self.url + path, data=body, method=method, headers=supplied)
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                return json.loads(response.read())
        except HTTPError as error:
            try:
                message = json.loads(error.read()).get('error', 'APIリクエストに失敗しました。')
            except (ValueError, UnicodeError):
                message = 'APIリクエストに失敗しました。'
            raise RuntimeError(f'HTTP {error.code}: {message}') from None

    def analyze_file(self, path, style='following', profile='standard'):
        path = Path(path)
        if not 0 < path.stat().st_size <= MAX_BYTES:
            raise ValueError('1ファイル512 MB以内で選んでください。')
        # Streaming the file avoids buffering a 512 MB upload in memory.
        with path.open('rb') as source:
            return self.request('/jobs/upload', 'POST', source, {
                'Content-Length': str(path.stat().st_size),
                'Content-Type': 'application/octet-stream',
                'X-Media-Title': base64.b64encode(path.stem.encode('utf-8')).decode('ascii'),
                'X-Generation-Style': style, 'X-Music-Profile': profile})

    def analyze_video(self, video_id, style='following', profile='standard'):
        if not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
            raise ValueError('--video-idにはURLではなく11文字の動画IDを指定してください。')
        body = json.dumps(dict(videoID=video_id, style=style, profile=profile)).encode('utf-8')
        return self.request('/jobs', 'POST', body, {'Content-Type': 'application/json'})

    def wait(self, job_id, timeout=1800):
        if not re.fullmatch(r'[0-9a-f-]{36}', job_id):
            raise ValueError('解析IDが正しくありません。')
        deadline = time.monotonic() + timeout
        try:
            while time.monotonic() < deadline:
                status = self.request('/jobs/' + job_id)
                if status['state'] == 'done':
                    return status['track']
                if status['state'] in ('failed', 'canceled'):
                    raise RuntimeError(status['message'])
                print(f"{status['progress']:.0%} {status['message']}", file=sys.stderr)
                time.sleep(1)
            raise TimeoutError('解析が30分以内に終了しませんでした。')
        except (KeyboardInterrupt, TimeoutError):
            self.request('/jobs/' + job_id, 'DELETE')
            raise


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--connection', type=Path, default=ROOT / '.pc-server' / 'connection.json')
    parser.add_argument('--url', help='別のPCのURL。キーはHAPTICLAB_TOKEN環境変数で指定')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('health')
    commands.add_parser('tracks')
    commands.add_parser('openapi')
    get = commands.add_parser('get-track')
    get.add_argument('track_id')
    get.add_argument('--output', type=Path, required=True)
    analyze = commands.add_parser('analyze')
    source = analyze.add_mutually_exclusive_group(required=True)
    source.add_argument('--file', type=Path)
    source.add_argument('--video-id')
    analyze.add_argument('--style', choices=['following', 'musical'], default='following')
    analyze.add_argument('--profile', choices=['standard', 'orchestral'], default='standard')
    analyze.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.url:
            url, token = args.url, os.environ.get('HAPTICLAB_TOKEN', '')
        else:
            connection = json.loads(args.connection.read_text(encoding='utf-8-sig'))
            port = urlsplit(connection['addresses'][0]).port or 8765
            url, token = f'http://127.0.0.1:{port}', connection['token']
        client = APIClient(url, token)
        if args.command in ('health', 'tracks', 'openapi'):
            path = '/openapi.json' if args.command == 'openapi' else '/' + args.command
            print(json.dumps(client.request(path), ensure_ascii=False, indent=2))
            return 0
        if args.command == 'get-track':
            if not re.fullmatch(r'[0-9a-f]{64}', args.track_id):
                raise ValueError('保存IDが正しくありません。')
            track = client.request('/tracks/' + args.track_id)
        else:
            job = (client.analyze_file(args.file, args.style, args.profile) if args.file
                   else client.analyze_video(args.video_id, args.style, args.profile))
            track = client.wait(job['id'])
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(track, ensure_ascii=False, allow_nan=False), encoding='utf-8')
        print(json.dumps(dict(output=str(args.output), duration=track['duration'],
                              trackID=track['analysis']['serverTrackID']), ensure_ascii=False))
        return 0
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('解析をキャンセルしました。', file=sys.stderr)
        return 130


if __name__ == '__main__':
    raise SystemExit(main())
