"""Run actual pretrained inference; media stays in the ignored private directory."""
import argparse
import hashlib
from pathlib import Path
import sys
import time
import numpy as np
import soundfile as sf
from signal_analysis import decode, RATE
from music_ai import analyze_music, write_json


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, default=Path('.pc-server/verification/serenade'))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    pcm, duration = decode(args.source, args.output / 'decoded.f32')
    digest = hashlib.sha256(np.asarray(pcm).tobytes()).hexdigest()
    wav = args.output / 'canonical.wav'
    sf.write(wav, pcm, RATE, subtype='FLOAT')
    pcm._mmap.close()
    def progress(fraction, message):
        print(f'{time.monotonic()-start:.1f}s {fraction:.0%} {message}', flush=True)
    graph = analyze_music(wav, args.output, Path('.pc-server/models'), duration, digest, progress)
    print('Analysis complete:', duration, 'seconds,', len(graph['structure']['segments']), 'sections', flush=True)
    write_json(args.output / 'run-metrics.json', dict(elapsedSeconds=time.monotonic()-start, duration=duration,
                                                    sections=graph['structure']['segments'], timings=graph['timings']))


if __name__ == '__main__':
    main()
