#!/usr/bin/env bash
# One-time setup for the muttr TTS sidecar. Creates a local venv using a
# Python >= 3.10 interpreter (mlx-audio drops 3.9) and installs deps.
# Re-run whenever requirements.txt changes.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

find_python() {
    for p in python3.13 python3.12 python3.11 python3.10; do
        if command -v "$p" >/dev/null 2>&1; then
            echo "$p"
            return 0
        fi
    done
    # Fallback: plain python3 only if it's >= 3.10
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c 'import sys; exit(0 if sys.version_info >= (3,10) else 1)'; then
            echo "python3"
            return 0
        fi
    fi
    return 1
}

if ! PY=$(find_python); then
    cat >&2 <<EOF
muttr-tts: no Python >= 3.10 found on PATH.

macOS system python3 is 3.9, which mlx-audio no longer supports.
Install a modern Python, e.g.:
  brew install python@3.12
Then re-run ./setup.sh.
EOF
    exit 1
fi

echo "muttr-tts: using $PY ($("$PY" --version))"

# If an existing venv was built with an older Python, rebuild it.
if [[ -d .venv ]]; then
    current=$(.venv/bin/python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "none")
    wanted=$("$PY" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    if [[ "$current" != "$wanted" ]]; then
        echo "muttr-tts: recreating venv (was $current, want $wanted)"
        rm -rf .venv
    fi
fi

"$PY" -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

echo "muttr-tts: setup complete. Run ./run.sh to start the sidecar."
