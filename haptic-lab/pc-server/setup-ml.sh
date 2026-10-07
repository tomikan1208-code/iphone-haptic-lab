#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v uv >/dev/null 2>&1; then
  echo 'Install uv: https://docs.astral.sh/uv/getting-started/installation/' >&2
  exit 1
fi
if ! command -v git >/dev/null 2>&1; then
  echo 'Install Git to download the pinned inference code.' >&2
  exit 1
fi
if [[ ! -f .pc-server/ml-venv/bin/python ]]; then
  uv venv .pc-server/ml-venv --python 3.11
fi
index_args=()
if [[ "$(uname -s)" != 'Darwin' ]]; then
  torch_index='https://download.pytorch.org/whl/cu124'
  if [[ "${1:-}" == '--cpu' ]]; then torch_index='https://download.pytorch.org/whl/cpu'; fi
  uv pip install --python .pc-server/ml-venv/bin/python torch==2.5.1 torchaudio==2.5.1 --index-url "$torch_index"
  index_args=(--extra-index-url "$torch_index" --index-strategy unsafe-best-match)
fi
uv pip install --python .pc-server/ml-venv/bin/python -r pc-server/requirements-ml.txt "${index_args[@]}"
.pc-server/ml-venv/bin/python pc-server/check-ml.py
echo 'Music AI is ready. First analysis downloads model weights; later runs reuse them.'
