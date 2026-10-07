"""Pretrained music analysis. Neural inference stays on the PC, never an LLM.

The Windows port changes attention/DSP implementations, not the trained All-In-One
weights. Stages release GPU models before loading the next one on an 8 GB card.
"""
import gc
import hashlib
import json
import os
from pathlib import Path
import random
import time

import numpy as np
from music_rhythm import estimate_tempo

PIPELINE_VERSION = 'arrangement-3.4'
ALLINONE_COMMIT = '8414233b743d6ccec46e36ab4cfeddb4605ff3bf'
CLAP_REVISION = '8fa0f1c6d0433df6e97c127f64b2a1d6c0dcda8a'
BEAT_SHA256 = '8c328b45f59d8dd3dff219253ff6a8d6482be57d0133a29140e2febbf8eb8331'
BEAT_MIRROR_REVISION = 'a44f51ed621bc9895c15f8b46194cf16d7b22b66'
MODEL_SPEC = dict(structure='harmonix-all', port=ALLINONE_COMMIT,
                  separation='htdemucs', rhythm='beat-this-final0@' + BEAT_SHA256,
                  separationPort='ffe0080ef96336a34e3f0ee8ba22ceaa0623a36c',
                  seed='20261007', semantics='laion/clap-htsat-unfused@' + CLAP_REVISION)
MOOD_PROMPTS = {
    'driving': 'Energetic driving music with a strong dance groove and punchy drums.',
    'gentle': 'Gentle delicate music with soft intimate vocals and a restrained rhythm.',
    'tense': 'Dark tense dramatic music with restless rhythms and sharp accents.',
    'floating': 'Dreamy atmospheric floating music with sustained textures and spacious sounds.',
    'bright': 'Bright joyful playful music with light bouncy rhythms.',
    'solemn': 'Solemn melancholic reflective music with emotional vocals and a slow sustained feel.',
}


def cache_identity(audio_sha256, profile='standard'):
    payload = dict(audio=audio_sha256, pipeline=PIPELINE_VERSION, models=MODEL_SPEC, profile=profile)
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def write_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, allow_nan=False), encoding='utf-8')
    temporary.replace(path)


def release_gpu():
    import torch
    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()


def configure_models(cache):
    cache = Path(cache).resolve()
    cache.mkdir(parents=True, exist_ok=True)
    os.environ['TORCH_HOME'] = str(cache / 'torch')
    os.environ['HF_HOME'] = str(cache / 'huggingface')
    os.environ['HF_HUB_DISABLE_SYMLINKS_WARNING'] = '1'
    import torch
    torch.set_num_threads(min(8, os.cpu_count() or 4))
    torch.manual_seed(20261007)
    random.seed(20261007)
    np.random.seed(20261007)
    return 'cuda' if torch.cuda.is_available() else 'cpu'


def separate(wav, folder, device):
    import soundfile as sf
    import torch
    from demucs_infer.checkpoint_runtime import CheckpointRuntime
    from demucs_infer.apply import apply_model
    destination = folder / 'stems' / 'htdemucs' / wav.stem
    destination.mkdir(parents=True, exist_ok=True)
    required = ['bass', 'drums', 'other', 'vocals']
    if all((destination / (name + '.wav')).exists() for name in required):
        return destination
    samples, rate = sf.read(wav, dtype='float32', always_2d=True)
    if rate != 44100 or samples.shape[1] != 2:
        raise ValueError('AI解析には44.1 kHzのステレオ音源が必要です。')
    mix = torch.from_numpy(samples.T.copy())
    demucs_cache = Path(os.environ['TORCH_HOME']).parent / 'demucs'
    model = CheckpointRuntime('htdemucs', cache_dir=demucs_cache).load_registered_model().to(device).eval()
    # The reference Demucs CLI normalizes the input and restores its scale.
    reference = mix.mean(0)
    mean, deviation = reference.mean(), reference.std().clamp_min(1e-8)
    normalized = (mix - mean) / deviation
    with torch.inference_mode():
        sources = apply_model(model, normalized[None], device=device, shifts=1,
                              split=True, overlap=.25, progress=True)[0].cpu()
    sources = sources * deviation + mean
    for name, data in zip(model.sources, sources):
        # PCM16 follows the original All-In-One spectrogram input contract.
        peak = float(data.abs().max())
        if peak > 1: data = data / peak
        sf.write(destination / (name + '.wav'), data.T.numpy(), rate, subtype='PCM_16')
    del sources, normalized, model, mix
    release_gpu()
    return destination


def stem_features(wav, stems, duration):
    import librosa
    import soundfile as sf
    rate, hop, window = 22050, 220, 1024
    times = np.arange(0, duration, .02)
    output = {'times': times.tolist()}
    for name, path in [('mix', wav)] + [(n, stems / (n + '.wav')) for n in ('bass', 'drums', 'vocals', 'other')]:
        y, sr = sf.read(path, dtype='float32', always_2d=True)
        stereo = librosa.resample(y.T, orig_sr=sr, target_sr=rate)
        mono = stereo.mean(axis=0)
        channel_power = np.mean(stereo**2, axis=1)
        if float(np.mean(mono**2)) < .02*float(channel_power.mean()):
            mono = stereo[int(np.argmax(channel_power))]
        rms = librosa.feature.rms(y=stereo, frame_length=window, hop_length=hop)[:, 0, :].mean(axis=0)
        axis = librosa.frames_to_time(np.arange(len(rms)), sr=rate, hop_length=hop)
        flux = librosa.onset.onset_strength(y=mono, sr=rate, hop_length=hop, n_fft=window)
        flux_axis = librosa.frames_to_time(np.arange(len(flux)), sr=rate, hop_length=hop)
        output[name] = np.interp(times, axis, rms).tolist()
        if name in ('bass', 'drums', 'vocals'):
            output[name + 'Onset'] = np.interp(times, flux_axis, flux).tolist()
    return output


def structure(wav, folder, device, duration):
    import allin1_infer
    from allin1_infer.config import HARMONIX_LABELS
    result = allin1_infer.analyze(wav, out_dir=folder / 'structure',
        device=device, model='harmonix-all', include_activations=True,
        demix_dir=folder / 'stems', spec_dir=folder / 'spectrogram',
        skip_separation=True, keep_byproducts=True, multiprocess=False)
    fps = float(result.activation_fps)
    labels = result.activations['label']
    sections = []
    for index, segment in enumerate(result.segments):
        start, end = max(0, float(segment.start)), min(duration, float(segment.end))
        if end <= start: continue
        probabilities = labels[:, max(0, int(start * fps)):min(labels.shape[-1], int(end * fps))].mean(axis=1)
        confidence = float(np.clip(probabilities[HARMONIX_LABELS.index(segment.label)], 0, 1))
        sections.append(dict(id='s' + str(index), start=start, end=end, label=segment.label,
                             confidence=confidence,
                             alternatives={label: float(p) for label, p in zip(HARMONIX_LABELS, probabilities)}))
    data = dict(segments=sections, beats=list(map(float, result.beats)),
                downbeats=list(map(float, result.downbeats)),
                beatPositions=list(map(int, result.beat_positions)),
                tempoBPM=estimate_tempo(result.beats), modelTempoBPM=float(result.bpm),
                activationFPS=fps)
    del result, labels
    release_gpu()
    return data


def rhythm(wav, device):
    import torch
    import urllib.request
    from beat_this.inference import File2Beats
    checkpoint = Path(torch.hub.get_dir()) / 'checkpoints' / 'beat_this-final0.ckpt'
    if not checkpoint.exists():
        checkpoint.parent.mkdir(parents=True, exist_ok=True)
        temporary = checkpoint.with_suffix('.download')
        urls = ['https://cloud.cp.jku.at/public.php/dav/files/7ik4RrBKTS273gp/final0.ckpt',
                'https://huggingface.co/rtikw/localmusic-assets/resolve/' + BEAT_MIRROR_REVISION + '/analysis/beat_this-final0.ckpt']
        for url in urls:
            try:
                with urllib.request.urlopen(url, timeout=30) as response, temporary.open('wb') as output:
                    import shutil
                    shutil.copyfileobj(response, output)
                with temporary.open('rb') as source:
                    actual = hashlib.file_digest(source, 'sha256').hexdigest()
                if actual != BEAT_SHA256:
                    raise ValueError('Beat Thisのモデルファイルが既知のSHA-256と一致しません。')
                temporary.replace(checkpoint)
                break
            except OSError:
                temporary.unlink(missing_ok=True)
        else:
            raise ValueError('拍のモデルを取得できません。PCのネットワーク接続を確認してください。')
    with checkpoint.open('rb') as source:
        if hashlib.file_digest(source, 'sha256').hexdigest() != BEAT_SHA256:
            raise ValueError('Beat Thisのモデルファイルが破損しています。')
    tracker = File2Beats(checkpoint_path=str(checkpoint), device=device, float16=False, dbn=False)
    beats, downbeats = tracker(wav)
    data = dict(beats=list(map(float, beats)), downbeats=list(map(float, downbeats)))
    del tracker
    release_gpu()
    return data


def semantics(wav, sections, device):
    import librosa
    import soundfile as sf
    import torch
    from transformers import ClapModel, ClapProcessor
    repository = 'laion/clap-htsat-unfused'
    processor = ClapProcessor.from_pretrained(repository, revision=CLAP_REVISION)
    model = ClapModel.from_pretrained(repository, revision=CLAP_REVISION).to(device).eval()
    text = processor(text=list(MOOD_PROMPTS.values()), padding=True, return_tensors='pt')
    with torch.inference_mode():
        text_embeddings = model.get_text_features(**{k: v.to(device) for k, v in text.items()})
        text_embeddings = torch.nn.functional.normalize(text_embeddings, dim=-1)
    y, rate = sf.read(wav, dtype='float32', always_2d=True)
    # Keep early and late phrases for long sections rather than truncating the entire section.
    for section in sections:
        length = section['end'] - section['start']
        centers = [section['start'] + length * f for f in ([.25, .75] if length > 16 else [.5])]
        similarities = []
        for center in centers:
            start = max(section['start'], center - 5)
            end = min(section['end'], start + 10)
            audio = librosa.resample(y[int(start * rate):int(end * rate)].mean(axis=1),
                                    orig_sr=rate, target_sr=48000)
            inputs = processor(audios=audio, sampling_rate=48000, return_tensors='pt')
            with torch.inference_mode():
                embedding = model.get_audio_features(**{k: v.to(device) for k, v in inputs.items()})
                embedding = torch.nn.functional.normalize(embedding, dim=-1)
                similarities.append((embedding @ text_embeddings.T)[0].cpu().numpy())
        scores = np.mean(similarities, axis=0)
        # Relative cosine similarity is NOT a calibrated probability or lyrical interpretation.
        section['moodSimilarities'] = dict(zip(MOOD_PROMPTS, map(float, scores)))
        section['mood'] = list(MOOD_PROMPTS)[int(np.argmax(scores))]
    del model, processor, text_embeddings
    release_gpu()


def analyze_music(wav, folder, model_cache, duration, audio_sha256, progress):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    completed = folder / 'analysis-graph.json'
    if completed.exists():
        graph = json.loads(completed.read_text(encoding='utf-8'))
        if graph.get('cacheID') == cache_identity(audio_sha256):
            return graph
    # Libraries also cache stems/spectrograms by filename. Isolate those by
    # content and model configuration when a caller reuses a work directory.
    intermediates = folder / 'intermediates' / cache_identity(audio_sha256)
    intermediates.mkdir(parents=True, exist_ok=True)
    device = configure_models(model_cache)
    timings = {}
    def stage(name, fraction, message, call):
        progress(fraction, message)
        started = time.monotonic()
        value = call()
        timings[name] = time.monotonic() - started
        return value
    stems = stage('separation', .19, 'AIがドラム・ベース・歌・伴奏を分離しています',
                  lambda: separate(Path(wav), intermediates, device))
    musical = stage('structure', .40, 'AIがサビ・Aメロ・展開と拍を推定しています',
                    lambda: structure(Path(wav), intermediates, device, duration))
    rhythm_result = stage('rhythm', .64, '別のAIで拍と小節の位置を確認しています',
                          lambda: rhythm(Path(wav), device))
    features = stage('features', .73, '分離した楽器の強弱とアタックを分析しています',
                     lambda: stem_features(Path(wav), stems, duration))
    stage('semantics', .80, '音楽の雰囲気を音声モデルで比較しています',
          lambda: semantics(Path(wav), musical['segments'], device))
    graph = dict(version=1, cacheID=cache_identity(audio_sha256), audioSHA256=audio_sha256,
                 duration=duration, pipeline=PIPELINE_VERSION, models=MODEL_SPEC, device=device,
                 structure=musical, rhythm=rhythm_result, features=features, timings=timings,
                 semanticsNote='Relative CLAP cosine similarities; not probabilities or lyric interpretation.')
    import torch
    graph['peakCUDAAllocatedMiB'] = torch.cuda.max_memory_allocated()/2**20 if device == 'cuda' else None
    checkpoint_root = Path(model_cache) / 'torch' / 'hub' / 'checkpoints'
    checkpoints = [p for p in checkpoint_root.glob('*') if p.is_file()]
    checkpoints += [p for p in (Path(model_cache)/'demucs').rglob('*') if p.is_file() and p.suffix in ('.th','.pth','.pt','.ckpt')]
    graph['checkpointSHA256'] = {}
    for path in checkpoints:
        with path.open('rb') as data:
            graph['checkpointSHA256'][path.name] = hashlib.file_digest(data, 'sha256').hexdigest()
    write_json(completed, graph)
    return graph
