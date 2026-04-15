#!/usr/bin/env bash
# Start the muttr TTS sidecar using the local venv. Pass env overrides via the
# shell, e.g. MUTTR_TTS_MODEL=mlx-community/Qwen3-TTS-0.6B-4bit ./run.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

if [[ ! -d .venv ]]; then
    echo "muttr-tts: venv missing — run ./setup.sh first" >&2
    exit 1
fi

# shellcheck disable=SC1091
source .venv/bin/activate
exec python3 tts_server.py
