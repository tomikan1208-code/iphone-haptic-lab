"""Authenticated LAN companion for the iPhone music player."""
import argparse
import base64
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
from urllib.parse import urlsplit
import uuid

ROOT = Path(__file__).resolve().parent.parent
PRIVATE = ROOT / '.pc-server'
DATA = PRIVATE / 'data'
MAX_BYTES = 512 * 1024 * 1024
STYLES = {'following', 'musical'}


class Companion:
    def __init__(self, root=DATA, token=None):
        self.root = Path(root).resolve()
        self.working = self.root / 'working'
        self.tracks = self.root / 'tracks'
        self.working.mkdir(parents=True, exist_ok=True)
        self.tracks.mkdir(parents=True, exist_ok=True)
        self.token = token or secrets.token_urlsafe(32)
        self.jobs = {}
        self.lock = threading.RLock()
        self.worker_slot = threading.Semaphore(1)

    def health(self):
        return dict(protocolVersion=1, profile='44.1 kHz / 4096 FFT / 10 ms',
            youtubeAvailable=importlib.util.find_spec('yt_dlp') is not None)

    def create_job(self, title, style, video_id=None, profile='standard'):
        if style not in STYLES:
            raise ValueError('振動の作り方が正しくありません。')
        if profile not in ('standard', 'orchestral'):
            raise ValueError('仕上げが正しくありません。')
        if video_id is not None and (not isinstance(video_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id)):
            raise ValueError('動画IDが正しくありません。')
        with self.lock:
            busy = [job for job in self.jobs.values() if not job.get('ended')]
            if len(busy) >= 8:
                raise ValueError('PCの解析待ちが多いため、少し待ってから試してください。')
            identity = str(uuid.uuid4())
            folder = self.working / identity
            folder.mkdir()
            request = dict(title=str(title)[:300], style=style, profile=profile)
            if video_id:
                request['videoID'] = video_id
            (folder / 'request.json').write_text(json.dumps(request, ensure_ascii=False), encoding='utf-8')
            self.jobs[identity] = dict(folder=folder, process=None, canceled=False, ended=False, created=time.time())
        return identity

    def start_job(self, identity):
        def work():
            job = self.jobs[identity]
            with self.worker_slot:
                if job['canceled']:
                    job['ended'] = True
                    return
                folder = job['folder']
                environment = dict(os.environ, PYTHONUTF8='1')
                with (folder / 'worker.log').open('wb') as log:
                    with self.lock:
                        if job['canceled']:
                            job['ended'] = True
                            return
                        job['process'] = subprocess.Popen([sys.executable, str(ROOT / 'pc-server' / 'worker.py'), str(folder)],
                            stdout=log, stderr=log, env=environment, creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
                    job['process'].wait()
                job['ended'] = True
                self.clean_source(job)
        threading.Thread(target=work, daemon=True).start()

    def clean_source(self, job):
        # Resolve only files owned by this request; no user-selected path is deleted.
        folder = job['folder'].resolve()
        if folder.parent != self.working or not re.fullmatch(r'[0-9a-f-]{36}', folder.name):
            return
        for path in folder.iterdir():
            if path.name.startswith(('source', 'decoded')) and path.is_file():
                try:
                    path.unlink()
                except OSError:
                    pass

    def status(self, identity):
        job = self.jobs.get(identity)
        if not job:
            raise FileNotFoundError('解析が見つかりません。')
        if job['canceled']:
            return dict(id=identity, state='canceled', progress=0, message='解析をキャンセルしました。')
        path = job['folder'] / 'status.json'
        status = json.loads(path.read_text(encoding='utf-8')) if path.exists() else dict(
            state='failed' if job['ended'] else 'queued', progress=0,
            message='PCの処理に失敗しました。ログを確認してください。' if job['ended'] else 'PCの解析待ちです')
        status['id'] = identity
        if status['state'] == 'done':
            track_id = status['trackID']
            if not re.fullmatch(r'[0-9a-f]{64}', track_id):
                raise ValueError('PCの保存データが正しくありません。')
            path = self.tracks / (track_id + '.json')
            if path.exists():
                status['track'] = json.loads(path.read_text(encoding='utf-8'))
            else:
                status.update(state='failed', message='PCの保存データは削除されました。')
        return status

    def cancel(self, identity):
        with self.lock:
            job = self.jobs.get(identity)
            if not job:
                raise FileNotFoundError('解析が見つかりません。')
            job['canceled'] = True
            (job['folder'] / 'cancel').touch()
            process = job['process']
            if process and process.poll() is None:
                process.terminate()
            if process is None:
                job['ended'] = True
            self.clean_source(job)

    def stored_tracks(self):
        values = []
        for path in self.tracks.glob('*.meta.json'):
            try:
                value = json.loads(path.read_text(encoding='utf-8'))
                if re.fullmatch(r'[0-9a-f]{64}', value['id']) and (self.tracks / (value['id'] + '.json')).exists():
                    values.append(value)
            except (ValueError, KeyError):
                continue
        return sorted(values, key=lambda value: value['createdAt'], reverse=True)

    def delete_track(self, identity):
        if not re.fullmatch(r'[0-9a-f]{64}', identity):
            raise ValueError('保存IDが正しくありません。')
        for suffix in ['.json', '.meta.json']:
            (self.tracks / (identity + suffix)).unlink(missing_ok=True)


class Handler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    def log_message(self, *_):
        pass

    def respond(self, status, value):
        data = json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',', ':')).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Connection', 'close')
        self.end_headers()
        self.close_connection = True
        self.wfile.write(data)

    def handle_api(self):
        companion = self.server.companion
        address = ipaddress.ip_address(self.client_address[0])
        supplied = self.headers.get('Authorization', '').encode()
        expected = ('Bearer ' + companion.token).encode()
        if not (address.is_private or address.is_loopback) or not hmac.compare_digest(supplied, expected):
            self.respond(401, dict(error='接続キーが正しくありません。'))
            return
        parts = urlsplit(self.path).path.strip('/').split('/')
        try:
            if self.command == 'GET' and parts == ['health']:
                self.respond(200, companion.health())
            elif self.command == 'GET' and parts == ['tracks']:
                self.respond(200, companion.stored_tracks())
            elif self.command == 'POST' and parts == ['shutdown']:
                self.respond(200, dict(stopping=True))
                threading.Thread(target=self.server.shutdown, daemon=True).start()
            elif self.command == 'DELETE' and len(parts) == 2 and parts[0] == 'tracks':
                companion.delete_track(parts[1])
                self.respond(200, dict(deleted=True))
            elif len(parts) == 2 and parts[0] == 'jobs' and self.command in ('GET', 'DELETE'):
                if self.command == 'DELETE':
                    companion.cancel(parts[1])
                    self.respond(200, dict(canceled=True))
                else:
                    self.respond(200, companion.status(parts[1]))
            elif self.command == 'POST' and parts in (['jobs'], ['jobs', 'upload']):
                self.connection.settimeout(120)
                length = int(self.headers.get('Content-Length', '0'))
                if parts == ['jobs']:
                    if not 0 < length <= 16384:
                        raise ValueError('解析リクエストが正しくありません。')
                    value = json.loads(self.rfile.read(length))
                    if not isinstance(value, dict) or not value.get('videoID'):
                        raise ValueError('動画IDが必要です。')
                    identity = companion.create_job(value.get('title', 'YouTube動画'), value.get('style', 'following'), value.get('videoID'), value.get('profile', 'standard'))
                else:
                    if not 0 < length <= MAX_BYTES:
                        raise ValueError('1ファイル512 MB以内で選んでください。')
                    title = base64.b64decode(self.headers.get('X-Media-Title', ''), validate=True).decode('utf-8')
                    identity = companion.create_job(title or '音源', self.headers.get('X-Generation-Style', 'following'), profile=self.headers.get('X-Music-Profile', 'standard'))
                    job = companion.jobs[identity]
                    try:
                        with (job['folder'] / 'source').open('wb') as destination:
                            remaining = length
                            while remaining:
                                chunk = self.rfile.read(min(65536, remaining))
                                if not chunk:
                                    raise ValueError('音源の送信が途中で終了しました。')
                                destination.write(chunk)
                                remaining -= len(chunk)
                    except Exception:
                        companion.cancel(identity)
                        raise
                companion.start_job(identity)
                self.respond(202, dict(id=identity, state='queued', progress=0, message='PCの解析待ちです'))
            else:
                self.respond(404, dict(error='この操作はありません。'))
        except FileNotFoundError as error:
            self.respond(404, dict(error=str(error)))
        except (ValueError, KeyError, TypeError, UnicodeError) as error:
            self.respond(400, dict(error=str(error)[:300]))
        except (ConnectionError, TimeoutError, BrokenPipeError):
            self.close_connection = True
        except Exception:
            self.respond(500, dict(error='PCサーバーの処理に失敗しました。'))

    do_GET = handle_api
    do_POST = handle_api
    do_DELETE = handle_api


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    PRIVATE.mkdir(exist_ok=True)
    token_file = PRIVATE / 'server-key.txt'
    token = token_file.read_text().strip() if token_file.exists() else secrets.token_urlsafe(32)
    token_file.write_text(token, encoding='utf-8')
    companion = Companion(token=token)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.companion = companion
    addresses = ['127.0.0.1']
    if args.host != '127.0.0.1':
        addresses = [address for address in socket.gethostbyname_ex(socket.gethostname())[2]
                     if ipaddress.ip_address(address).is_private and not address.startswith('127.')] or addresses
    urls = ['http://' + address + ':' + str(args.port) for address in addresses]
    (PRIVATE / 'connection.json').write_text(json.dumps(dict(addresses=urls, token=token), indent=2), encoding='utf-8')
    print(json.dumps(dict(status='listening', addresses=urls), ensure_ascii=False), flush=True)
    try:
        server.serve_forever()
    finally:
        for identity in list(companion.jobs):
            if not companion.jobs[identity]['ended']:
                companion.cancel(identity)
        server.server_close()


if __name__ == '__main__':
    main()
