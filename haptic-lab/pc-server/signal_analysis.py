"""Local audio analysis and musical haptic composition. No cloud inference."""
import math
import re
import subprocess
from pathlib import Path

import numpy as np
from imageio_ffmpeg import get_ffmpeg_exe

RATE = 44100
WINDOW = 4096
HOP = 441
MAX_SECONDS = 1200
BAND_COUNT = 24
BAND_EDGES = np.geomspace(20, 8000, BAND_COUNT + 1)


def decode(source: Path, destination: Path):
    ffmpeg = get_ffmpeg_exe()
    probe = subprocess.run([ffmpeg, '-hide_banner', '-i', str(source)], capture_output=True, timeout=30)
    match = re.search(r'Duration: (\d+):(\d+):(\d+(?:\.\d+)?)', probe.stderr.decode('utf-8', 'replace'))
    duration = None
    if match:
        duration = int(match[1]) * 3600 + int(match[2]) * 60 + float(match[3])
        if duration > MAX_SECONDS or duration <= 0:
            raise ValueError('1曲20分以内の音源を選んでください。')
    filters = 'aresample=async=1:first_pts=0' + (',apad' if duration else '')
    result = subprocess.run([ffmpeg, '-nostdin', '-hide_banner', '-loglevel', 'error', '-i', str(source),
        '-vn', '-af', filters, '-t', str(duration or MAX_SECONDS + 0.02), '-ac', '2', '-ar', str(RATE),
        '-f', 'f32le', '-y', str(destination)], capture_output=True, timeout=180)
    if result.returncode:
        raise ValueError('音源をデコードできません。保護されていない音楽ファイルを選んでください。')
    count = destination.stat().st_size // 8
    duration = count / RATE
    if not 0 < duration <= MAX_SECONDS:
        raise ValueError('音源が空か、20分を超えています。')
    return np.memmap(destination, dtype='<f4', mode='r', shape=(count, 2)), duration


def analyze(pcm, duration, digest, progress, canceled):
    nframes = int(math.ceil(len(pcm) / HOP))
    features = np.zeros((nframes, 7), dtype=np.float64)
    band_features = np.zeros((nframes, BAND_COUNT), dtype=np.float32)
    window = np.hanning(WINDOW).astype(np.float32)
    short_window = np.hanning(1024).astype(np.float32)
    frequencies = np.fft.rfftfreq(WINDOW, 1 / RATE)
    bass_bins = (frequencies >= 20) & (frequencies < 120)
    mid_bins = (frequencies >= 120) & (frequencies < 500)
    high_bins = (frequencies >= 500) & (frequencies <= 8000)
    band_bins = [(frequencies >= BAND_EDGES[index]) &
                 (frequencies < BAND_EDGES[index + 1]) for index in range(BAND_COUNT)]
    short_freq = np.fft.rfftfreq(1024, 1 / RATE)
    active = (short_freq > 0) & (short_freq <= 8000)
    previous = np.zeros((2, 513))
    for begin in range(0, nframes, 128):
        if canceled():
            raise InterruptedError('解析をキャンセルしました。')
        count = min(128, nframes - begin)
        first = begin * HOP - WINDOW // 2
        last = (begin + count - 1) * HOP + WINDOW // 2
        data = np.asarray(pcm[max(0, first):min(len(pcm), last)])
        data = np.pad(data, ((max(0, -first), max(0, last - len(pcm))), (0, 0)))
        frames = np.lib.stride_tricks.sliding_window_view(data, WINDOW, axis=0)[::HOP][:count]
        if not np.isfinite(frames).all() or np.max(np.abs(frames)) > 16:
            raise ValueError('音源に不正なサンプルがあります。')
        bass_spectrum = np.abs(np.fft.rfft(frames * window, axis=-1))
        short = frames[:, :, 1536:2560]
        rms = np.sqrt(np.mean(short * short, axis=-1)).mean(axis=1)
        bass = np.sqrt(np.sum(bass_spectrum[:, :, bass_bins] ** 2, axis=-1)).mean(axis=1) / WINDOW
        mid = np.sqrt(np.sum(bass_spectrum[:, :, mid_bins] ** 2, axis=-1)).mean(axis=1) / WINDOW
        high = np.sqrt(np.sum(bass_spectrum[:, :, high_bins] ** 2, axis=-1)).mean(axis=1) / WINDOW
        for band, bins in enumerate(band_bins):
            band_features[begin:begin + count, band] = np.sqrt(np.sum(bass_spectrum[:, :, bins] ** 2, axis=-1)).mean(axis=1) / WINDOW
        spectrum = np.abs(np.fft.rfft(short * short_window, axis=-1))
        preceding = np.concatenate([previous[None], spectrum[:-1]], axis=0)
        flux = np.maximum(0, spectrum - preceding)[:, :, active].sum(axis=(1, 2)) / 2048
        previous = spectrum[-1]
        magnitudes = spectrum[:, :, active]
        brightness = np.clip((magnitudes * short_freq[active]).sum(axis=(1, 2)) /
                             np.maximum(1e-12, magnitudes.sum(axis=(1, 2))) / 6000, 0, 1)
        times = np.arange(begin, begin + count) * HOP / RATE
        features[begin:begin + count] = np.column_stack([times, rms, bass, flux, brightness, mid, high])
        progress(0.15 + 0.50 * (begin + count) / nframes, '低音・音量・打音を精密解析しています')
    if features[:, 1].max() <= 0.00003:
        raise ValueError('振動を作れる音が見つかりませんでした。')
    def reference(values):
        positive = values[values > 0.00001]
        return max(0.00001, float(np.percentile(positive, 95))) if len(positive) else 1
    scales = [reference(features[:, column]) for column in [1, 2, 3, 5, 6]]
    spectrum_scale = max(reference(band_features.max(axis=1)), scales[0] * .35)
    envelope, taps, saved_spectrum = [], [], []
    smooth_bass = smooth_energy = smooth_mid = smooth_high = 0.0
    for index, (time, rms, bass, flux, brightness, mid, high) in enumerate(features):
        audible = rms > 0.00003
        energy = min(1, (rms / scales[0]) ** .7) if audible else 0
        low = min(1, (bass / scales[1]) ** .7) if audible else 0
        middle = min(1, (mid / scales[3]) ** .7) if audible else 0
        upper = min(1, (high / scales[4]) ** .7) if audible else 0
        smooth_bass += (low - smooth_bass) * (0.62 if low > smooth_bass else 0.30)
        smooth_energy += (energy - smooth_energy) * (0.62 if energy > smooth_energy else 0.30)
        smooth_mid += (middle - smooth_mid) * (0.62 if middle > smooth_mid else 0.30)
        smooth_high += (upper - smooth_high) * (0.62 if upper > smooth_high else 0.30)
        if not audible:
            smooth_bass = smooth_energy = smooth_mid = smooth_high = 0
        sharpness = min(1, .12 + brightness * .55 + smooth_high * .30) if audible else 0
        envelope.append(dict(time=float(time), bass=smooth_bass, energy=smooth_energy,
                             sharpness=float(sharpness), mid=smooth_mid, high=smooth_high))
        levels = np.round(np.clip((band_features[index] / spectrum_scale) ** .7, 0, 1), 3) if audible else np.zeros(BAND_COUNT)
        saved_spectrum.append(dict(time=float(time), levels=[round(float(level), 3) for level in levels]))
        local = features[max(0, index - 50):index, 3]
        threshold = max(scales[2] * .16, float(local.mean() + local.std() * .75) if len(local) else 0)
        before = features[index - 1, 3] if index else 0
        after = features[index + 1, 3] if index + 1 < len(features) else 0
        if audible and flux > threshold and flux > before and flux >= after and (not taps or time - taps[-1]['time'] >= .1):
            taps.append(dict(time=float(time), intensity=min(1, .2 + flux / scales[2] * .8) * math.sqrt(energy),
                             sharpness=min(1, float(sharpness) + .2)))
    envelope.append(dict(envelope[-1], time=duration))
    saved_spectrum.append(dict(saved_spectrum[-1], time=duration))
    return dict(version=2, audioSHA256=digest, duration=duration, envelope=envelope, taps=taps, spectrum=saved_spectrum)


def value(track, time):
    points = track['envelope']
    index = min(len(points) - 1, max(0, int(round(time / .01))))
    return points[index]


def estimate_beats(track):
    times = np.array([tap['time'] for tap in track['taps']])
    if len(times) > 3:
        differences = np.diff(times[:1000])
        differences = differences[differences > .1]
        while np.any(differences < 1 / 3):
            differences[differences < 1 / 3] *= 2
        while np.any(differences > 1):
            differences[differences > 1] /= 2
        histogram, edges = np.histogram(60 / differences, bins=np.arange(59.5, 181.5))
        bpm = float(60 + np.argmax(histogram))
        anchor = float(times[0])
    else:
        bpm, anchor = 120.0, 0.0
    beats = np.arange(anchor, track['duration'], 60 / bpm)
    return beats, beats[::4], bpm


def compose(track, beats, downbeats):
    # The network estimates musical timing. This mapper turns it into bounded, phrased haptics.
    taps = []
    downbeats = np.asarray(downbeats)
    for index, beat in enumerate(beats):
        time = float(beat)
        if not 0 <= time < track['duration']:
            continue
        point = value(track, time)
        energy = point['energy']
        if energy < .03:
            continue
        strong = bool(len(downbeats) and np.min(np.abs(downbeats - time)) < .08)
        intensity = (.82 if strong else .43) * math.sqrt(energy)
        if not taps or time - taps[-1]['time'] >= .1:
            taps.append(dict(time=time, intensity=intensity, sharpness=.55 if strong else .32))
        if energy > .75 and index + 1 < len(beats) and index % 4 < 3:
            offbeat = float((time + beats[index + 1]) / 2)
            if offbeat - time >= .12 and offbeat < track['duration'] and value(track, offbeat)['energy'] > .03:
                taps.append(dict(time=offbeat, intensity=.24 * energy, sharpness=.42))
    for point in track['envelope']:
        point['bass'] *= .45
        point['energy'] *= .35
        point['sharpness'] *= .6
        if 'mid' in point:
            point['mid'] *= .35
            point['high'] *= .6
    track['taps'] = taps
    return track


def orchestral(track):
    bass = energy = 0.0
    for point in track['envelope']:
        bass += (point['bass'] - bass) * (.08 if point['bass'] > bass else .03)
        energy += (point['energy'] - energy) * (.08 if point['energy'] > energy else .03)
        if point['energy'] == 0:
            bass = energy = 0
        point.update(bass=bass * .75, energy=energy * .6, sharpness=point['sharpness'] * .4)
        if 'mid' in point:
            point['mid'] *= .6
            point['high'] *= .4
    taps = []
    for tap in track['taps']:
        if tap['intensity'] > .65 and (not taps or tap['time'] - taps[-1]['time'] >= .75):
            taps.append(dict(time=tap['time'], intensity=tap['intensity'] * .4, sharpness=min(.35, tap['sharpness'])))
    track['taps'] = taps
    return track
