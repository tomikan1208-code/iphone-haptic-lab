"""Mark a verified interpreter so the lightweight server can advertise AI support."""
import importlib.metadata
import json
from pathlib import Path
import torch
import allin1_infer
from beat_this.inference import File2Beats
from transformers import ClapModel, ClapProcessor
from music_ai import PIPELINE_VERSION

if __name__ == '__main__':
    expected = {'all-in-one-infer':'3.1.0', 'demucs-infer':'4.4.0', 'madmom-infer':'0.3.0',
                'beat-this':'1.1.0', 'transformers':'4.51.1', 'librosa':'0.11.0', 'numpy':'2.2.6'}
    for name, version in expected.items():
        if importlib.metadata.version(name) != version:
            raise RuntimeError(name + ' must be ' + version + '; run setup-ml again.')
    if not torch.__version__.startswith('2.5.1'):
        raise RuntimeError('PyTorch 2.5.1 is required; run setup-ml again.')
    ready = dict(pipeline=PIPELINE_VERSION, cuda=torch.cuda.is_available(), torch=torch.__version__,
                 packages=expected)
    destination = Path(__file__).resolve().parent.parent / '.pc-server' / 'ml-ready.json'
    destination.write_text(json.dumps(ready), encoding='utf-8')
    print(json.dumps(ready))
