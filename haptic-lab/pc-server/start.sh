#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
host='127.0.0.1'
port='8765'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lan) host='0.0.0.0'; shift ;;
    --port) port="${2:?Specify a port}"; shift 2 ;;
    *) echo 'Usage: bash pc-server/start.sh [--lan] [--port 8765]' >&2; exit 2 ;;
  esac
done
if ! command -v uv >/dev/null 2>&1; then
  echo 'Install uv first: https://docs.astral.sh/uv/getting-started/installation/' >&2
  exit 1
fi
if [[ ! -f .pc-server/ml-venv/bin/python ]] || ! .pc-server/ml-venv/bin/python pc-server/check-ml.py; then
  bash pc-server/setup-ml.sh
fi
if [[ ! -f .pc-server/venv/bin/python ]]; then
  uv --cache-dir .build/uv-cache venv .pc-server/venv --python 3.13
fi
uv pip install --python .pc-server/venv/bin/python --cache-dir .build/uv-cache -r pc-server/requirements.txt
echo 'Connection settings: .pc-server/connection.json. Stop with Ctrl+C.'
exec .pc-server/venv/bin/python pc-server/server.py --host "$host" --port "$port"
