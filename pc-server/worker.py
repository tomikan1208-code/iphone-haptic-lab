import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time

from signal_analysis import analyze, compose, decode, estimate_beats, RATE

MAX_BYTES = 512 * 1024 * 1024


def atomic_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(',', ':')), encoding='utf-8')
    temporary.replace(path)


def run(folder):
    request = json.loads((folder / 'request.json').read_text(encoding='utf-8'))
    root = folder.parent.parent.resolve()
    assert folder.resolve().parent == root / 'working'
    style = request['style']
    profile = request.get('profile', 'standard')
    started = time.monotonic()
    pcm = None
    def canceled():
        return (folder / 'cancel').exists()
    def progress(fraction, message):
        atomic_json(folder / 'status.json', dict(state='running', progress=fraction, message=message))
        if canceled():
            raise InterruptedError('解析をキャンセルしました。')
    try:
        cache_key = request.get('videoID')
        source = folder / 'source'
        if not cache_key:
            with source.open('rb') as audio:
                digest = hashlib.file_digest(audio, 'sha256').hexdigest()
            cache_key = digest
        track_id = hashlib.sha256(('music-player-pc-v1:' + style + ':' + profile + ':' + cache_key).encode()).hexdigest()
        stored = root / 'tracks' / (track_id + '.json')
        if stored.exists():
            atomic_json(folder / 'status.json', dict(state='done', progress=1, message='PCに保存した振動を再利用します', trackID=track_id))
            return
        if request.get('videoID'):
            import yt_dlp
            video_id = request['videoID']
            if not re.fullmatch(r'[A-Za-z0-9_-]{11}', video_id):
                raise ValueError('YouTube動画IDが正しくありません。')
            def filter_video(info, *, incomplete=False):
                if info.get('is_live') or info.get('live_status') in ('is_live', 'is_upcoming'):
                    return 'ライブ配信は解析できません。'
                if info.get('duration', 0) > 1200:
                    return '1曲20分以内で選んでください。'
            def downloaded(info):
                if info.get('downloaded_bytes', 0) > MAX_BYTES:
                    raise ValueError('音源が512 MBを超えました。')
                total = info.get('total_bytes') or info.get('total_bytes_estimate') or 1
                progress(min(.12, info.get('downloaded_bytes', 0) / total * .12), 'YouTubeの音源をPCで取得しています')
            node = shutil.which('node')
            options = dict(format='bestaudio/best', noplaylist=True, quiet=True, no_warnings=True,
                outtmpl=str(folder / 'source.%(ext)s'), max_filesize=MAX_BYTES, socket_timeout=30,
                retries=2, fragment_retries=2, match_filter=filter_video, progress_hooks=[downloaded])
            if node:
                options['js_runtimes'] = {'node': {'path': node}}
            with yt_dlp.YoutubeDL(options) as downloader:
                info = downloader.extract_info('https://www.youtube.com/watch?v=' + video_id, download=True)
                if not info:
                    raise ValueError('この動画の音源を取得できませんでした。')
                source = Path(downloader.prepare_filename(info))
            if source.resolve().parent != folder.resolve() or source.stat().st_size > MAX_BYTES:
                raise ValueError('音源を取得できませんでした。')
            with source.open('rb') as audio:
                digest = hashlib.file_digest(audio, 'sha256').hexdigest()
        progress(.13, '音源をデコードしています')
        pcm, duration = decode(source, folder / 'decoded.f32')
        track = analyze(pcm, duration, digest, progress, canceled)
        bpm = None
        if profile == 'orchestral':
            from signal_analysis import orchestral
            track = orchestral(track)
        elif style == 'musical':
            beats, downbeats, bpm = estimate_beats(track)
            track = compose(track, beats, downbeats)
        pcm._mmap.close()
        pcm = None
        progress(.96, '振動を保存しています')
        track['analysis'] = dict(engine='pc', elapsedSeconds=time.monotonic() - started, sampleRate=RATE,
            hopMilliseconds=10, fftSize=4096, serverTrackID=track_id, style=style, tempoBPM=bpm, profile=profile)
        atomic_json(stored, track)
        atomic_json(root / 'tracks' / (track_id + '.meta.json'), dict(id=track_id, title=request.get('title', '音源')[:300],
            duration=duration, createdAt=time.time(), videoID=request.get('videoID'), style=style, profile=profile))
        atomic_json(folder / 'status.json', dict(state='done', progress=1, message='PCとiPhoneへ保存します', trackID=track_id))
    except InterruptedError:
        atomic_json(folder / 'status.json', dict(state='canceled', progress=0, message='解析をキャンセルしました。'))
    except Exception as error:
        # Never return tokens, local paths or raw extractor output to the phone.
        message = str(error) if isinstance(error, ValueError) else '音源の取得・解析に失敗しました。PCのログを確認し、ファイル解析でも試してください。'
        atomic_json(folder / 'status.json', dict(state='failed', progress=0, message=message[:500]))
        print(type(error).__name__ + ': ' + str(error), file=sys.stderr)
    finally:
        if pcm is not None:
            pcm._mmap.close()
        for path in folder.iterdir():
            if path.name.startswith('source') or path.name.startswith('decoded'):
                try:
                    path.unlink()
                except OSError:
                    pass


if __name__ == '__main__':
    run(Path(sys.argv[1]).resolve())
