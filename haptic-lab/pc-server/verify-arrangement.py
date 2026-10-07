"""Real end-to-end neural verification, including HTTP, cache, persistence and AHAP.

Needs the ML interpreter and model downloads. Run ordinary unit tests separately.
Source and stem audio are never copied into the report directory.
"""
import argparse
from collections import Counter
from http.server import ThreadingHTTPServer
import json
from pathlib import Path
import shutil
import threading
import time

import numpy as np
from jsonschema import Draft202012Validator
from client import APIClient
from haptic_arrangement import normalized
from music_ai import write_json
from server import Companion, Handler, ROOT, DATA, OPENAPI


def plot_result(track, graph, destination):
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    from matplotlib.patches import Patch
    plt.rcParams.update({'font.size': 9, 'axes.spines.top': False, 'axes.spines.right': False})
    fig, axes = plt.subplots(3, 1, figsize=(12, 7), sharex=True,
                             gridspec_kw={'height_ratios': [1.6, 1.6, .65]})
    times = graph['features']['times']
    for name, color in [('bass', '#765bd6'), ('drums', '#d98b20'), ('vocals', '#df6685')]:
        # A one-second average makes whole-track phrasing legible; analysis
        # and rendered haptics below retain their original time resolution.
        energy = np.convolve(normalized(graph['features'][name]), np.ones(51)/51, mode='same')
        axes[0].plot(times[::4], energy[::4], color=color,
                     alpha=.85, linewidth=.9, label=name)
    axes[0].set_title('natori - Serenade | AI structure estimates and arranged tactile voices', loc='left', fontsize=13)
    axes[0].set_ylabel('Relative stem energy\n(1-second mean)')
    axes[0].legend(loc='upper left', bbox_to_anchor=(0, -.015), ncol=3)
    axes[1].plot([p['time'] for p in track['envelope']], [p['intensity'] for p in track['envelope']],
                 color='#159b8c', linewidth=.9, label='sustained texture')
    axes[1].vlines([t['time'] for t in track['taps']], 0, [t['intensity'] for t in track['taps']],
                   color='#d27923', linewidth=.8, label='independent accents')
    axes[1].set_ylabel('Haptic intensity')
    axes[1].legend(loc='upper right', ncol=2)
    for axis in axes[:2]:
        axis.set_ylim(0, 1.1)
        axis.grid(axis='y', alpha=.12)
    colors = {'drive':'#168975','offbeat':'#40b5a7','pulse':'#6867bd','sparse':'#a29add',
              'breath':'#8dafce','rest':'#e6e8eb'}
    for bar in track['arrangement']['bars']:
        axes[2].axvspan(bar['start'], bar['end'], color=colors[bar['motif']], ymin=.1, ymax=.85)
    for section in track['arrangement']['sections']:
        if section['label'] == 'chorus':
            for axis in axes[:2]: axis.axvspan(section['start'], section['end'], color='#d7e8fa', alpha=.35)
            axes[0].text((section['start']+section['end'])/2, 1.03, 'chorus', ha='center', fontsize=8)
    axes[2].set_yticks([])
    axes[2].set_ylabel('Motifs')
    axes[2].legend(handles=[Patch(color=color, label=name) for name, color in colors.items()],
                   loc='upper center', bbox_to_anchor=(.5, 1.06), ncol=len(colors),
                   fontsize=7, framealpha=.9)
    axes[2].set_xlabel('Audio time (seconds)')
    axes[2].set_xlim(0, track['duration'])
    fig.text(.09, .015, 'All-In-One + HTDemucs + Beat This + CLAP. Labels are model estimates; tactile feel still needs an iPhone.', fontsize=8, color='#555')
    fig.tight_layout(rect=(0, .035, 1, 1))
    fig.savefig(destination, dpi=160)
    plt.close(fig)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--file', type=Path)
    parser.add_argument('--video-id', default='gNg2Qw5R-Q4')
    parser.add_argument('--report', type=Path, default=ROOT / 'docs' / 'verification')
    args = parser.parse_args()
    args.report.mkdir(parents=True, exist_ok=True)
    companion = Companion(DATA)
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    server.daemon_threads = True
    server.companion = companion
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    client = APIClient('http://127.0.0.1:' + str(server.server_port), companion.token)
    started = time.monotonic()
    def submit():
        if args.file: return client.analyze_file(args.file, 'arranged')
        body = json.dumps(dict(videoID=args.video_id, title='natori - Serenade', style='arranged')).encode()
        return client.request('/jobs', 'POST', body, {'Content-Type': 'application/json'})
    try:
        assert client.request('/health')['arrangementAvailable']
        job = submit()
        track = client.wait(job['id'])
        elapsed = time.monotonic()-started
        specification = json.loads(OPENAPI.read_text(encoding='utf-8'))
        Draft202012Validator({'$ref':'#/components/schemas/HapticTrack',
                              'components':specification['components']}).validate(track)
        identity = track['analysis']['serverTrackID']
        graph = json.loads((companion.tracks / (identity+'.graph.json')).read_text(encoding='utf-8'))
        assert track['version'] == 3
        assert all(a['time'] < b['time'] for a,b in zip(track['envelope'],track['envelope'][1:]))
        assert all(a['time'] < b['time'] for a,b in zip(track['taps'],track['taps'][1:]))
        assert all(0 <= p['intensity'] <= .45 for p in track['envelope'])
        assert all(0 <= t['time'] < track['duration'] and 0 <= t['intensity'] <= .8 for t in track['taps'])
        absolute = np.asarray(graph['features']['mix'])
        quiet = absolute <= max(.0001, float(absolute.max())*.008)
        assert all(track['envelope'][i]['intensity'] == 0 for i in np.flatnonzero(quiet))
        bundle = client.request('/tracks/'+identity+'/ahap')
        restored_taps = []
        for clip in bundle['manifest']['clips']:
            assert clip['duration'] <= 8
            for layer, filename in clip['files'].items():
                for item in bundle['files'][filename]['Pattern']:
                    if 'ParameterCurve' in item:
                        assert layer == 'bed'
                        curve = item['ParameterCurve']
                        points = curve['ParameterCurveControlPoints']
                        assert 2 <= len(points) <= 16
                        assert curve['Time']+points[-1]['Time'] <= clip['duration']+1e-6
                    if layer == 'accents':
                        restored_taps.append(round(clip['start']+item['Event']['Time'],6))
        assert restored_taps == [t['time'] for t in track['taps']]
        assert Companion(DATA).load_track(identity) == track
        repeated_start = time.monotonic()
        repeated = client.wait(submit()['id'])
        reuse_elapsed = time.monotonic()-repeated_start
        assert repeated == track
        for item in companion.jobs.values():
            if item['process']: item['process'].wait(timeout=30)
            assert not any(p.name.startswith(('source','decoded')) for p in item['folder'].iterdir())
            assert not (item['folder']/'model-work').exists()
        metrics = dict(videoID=args.video_id, title='natori - Serenade', duration=track['duration'],
            trackID=identity, elapsedSeconds=elapsed, analysisSeconds=track['analysis']['elapsedSeconds'],
            cacheReuseSeconds=reuse_elapsed, neuralStageSeconds=graph['timings'],
            peakCUDAAllocatedMiB=graph['peakCUDAAllocatedMiB'],
            beatAgreement=track['arrangement']['rhythmAgreement'],
            downbeatAgreement=track['arrangement']['downbeatAgreement'],
            tempoEstimateBPM=graph['structure']['tempoBPM'], sections=track['arrangement']['sections'],
            motifs=dict(Counter(b['motif'] for b in track['arrangement']['bars'])),
            taps=len(track['taps']), bars=len(track['arrangement']['bars']),
            maximumBed=max(p['intensity'] for p in track['envelope']),
            maximumTap=max((t['intensity'] for t in track['taps']), default=0),
            ahapClips=len(bundle['manifest']['clips']), ahapFiles=len(bundle['files']),
            models=graph['models'], checkpointSHA256=graph['checkpointSHA256'],
            checks=['full-track neural inference', 'HTTP schema', 'ordered finite hardware levels',
                    'quiet frames silent', 'AHAP tap round trip and independent curves',
                    'saved track reload', 'content/model/config cache reuse', 'temporary media cleanup'],
            limitations=['No manually annotated ground truth.', 'No iPhone hardware playback or Xcode build on this Windows PC.'])
        write_json(args.report / 'serenade-metrics.json', metrics)
        plot_result(track, graph, args.report / 'serenade-arrangement.png')
        # A paired 8-second chorus example can be imported individually into the lab.
        clip = next(c for c in bundle['manifest']['clips'] if c['start'] == 56)
        for layer, filename in clip['files'].items():
            write_json(args.report / ('serenade-56s-'+layer+'.ahap'), bundle['files'][filename])
        print(json.dumps({k:metrics[k] for k in ['duration','analysisSeconds','cacheReuseSeconds','beatAgreement',
                                                'downbeatAgreement','taps','bars','motifs','ahapFiles']}, ensure_ascii=False), flush=True)
    finally:
        for identity, item in companion.jobs.items():
            if not item['ended']: companion.cancel(identity)
        server.shutdown(); server.server_close(); thread.join(timeout=5)


if __name__ == '__main__':
    main()
