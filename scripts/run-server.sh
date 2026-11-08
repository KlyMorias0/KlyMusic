#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root/server"
if [ ! -x .venv/bin/python ]; then
  "${PYTHON:-python3}" -m venv .venv
  .venv/bin/python -m pip install -r requirements.txt
fi
exec .venv/bin/python -m uvicorn klymusic.app:app --host "${KLYMUSIC_BIND:-127.0.0.1}" --port "${KLYMUSIC_PORT:-8787}" --no-access-log
