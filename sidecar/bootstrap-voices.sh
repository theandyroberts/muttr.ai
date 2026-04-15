#!/usr/bin/env bash
# Generate 5 named reference clips for Qwen3-TTS voice cloning by using
# macOS's built-in `say` with distinct system voices. Qwen3 extracts timbre
# + accent from these — the listener hears Qwen3's rendering, not `say`.
#
# Usage:   ./bootstrap-voices.sh
# Output:  sidecar/voices/{samantha,daniel,moira,karen,rishi}.wav
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/voices"
mkdir -p "$out"

sample_text="The quick brown fox jumps over the lazy dog. This is a reference clip. \
My voice is distinct, steady, and clean — suitable for cloning."

# name:system-voice-name — pick voices with different accents so the
# resulting clones sound clearly distinct.
voices=(
  "samantha:Samantha"   # American female
  "daniel:Daniel"       # British male
  "moira:Moira"         # Irish female
  "karen:Karen"         # Australian female
  "rishi:Rishi"         # Indian male
)

for pair in "${voices[@]}"; do
  name="${pair%%:*}"
  system_voice="${pair##*:}"
  wav="$out/$name.wav"
  txt="$out/$name.txt"
  echo "→ $name.wav  (from system voice: $system_voice)"
  say -v "$system_voice" \
      -o "$wav" \
      --file-format=WAVE \
      --data-format=LEI16@22050 \
      "$sample_text"
  # Write the transcript alongside the clip so Qwen3 doesn't trigger a Whisper
  # STT download to re-derive it at runtime.
  printf '%s\n' "$sample_text" > "$txt"
done

echo ""
echo "Done. 5 reference clips in $out"
echo ""
echo "Try them:"
for pair in "${voices[@]}"; do
  name="${pair%%:*}"
  echo "  muttr --sidecar --voice $name -- claude \"...\""
done
