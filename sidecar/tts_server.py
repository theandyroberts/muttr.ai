#!/usr/bin/env python3
"""
Muttr local TTS sidecar.

Loads a TTS model once and serves synthesis over HTTP so the Swift app can
produce high-quality voiced narration. Default model is Qwen3-TTS via the
mlx-audio library; override with MUTTR_TTS_MODEL.

Endpoints:
  GET  /health      -> 200 {"ok": true, "model": "..."}
  POST /synthesize  -> WAV bytes
     Body JSON: {
       "text":    "What to say",
       "voice":   "voice-id-or-path-to-reference.wav",
       "rate":    0.5,     # optional playback rate hint (0-1)
       "pitch":   1.0,     # optional pitch multiplier
       "urgency": 1        # optional 1-4, nudges expressiveness
     }

Run:
  ./sidecar/run.sh
  or
  MUTTR_TTS_MODEL=mlx-community/Qwen3-TTS-0.6B-4bit python3 sidecar/tts_server.py

Env:
  MUTTR_TTS_MODEL    HF model id.
                     Defaults to mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit.
                     Alternatives:
                       mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit     (smaller/faster)
                       mlx-community/Qwen3-TTS-12Hz-1.7B-CustomVoice-8bit (for cloning)
                       mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-6bit (description-based)
  MUTTR_TTS_PORT     Port (default 7173)
  MUTTR_TTS_HOST     Bind host (default 127.0.0.1)
  MUTTR_VOICE_DIR    Directory of reference WAVs keyed by filename stem
"""

from __future__ import annotations

import inspect
import io
import json
import os
import sys
import tempfile
import threading
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Optional

MODEL_ID = os.environ.get("MUTTR_TTS_MODEL", "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-8bit")
PORT = int(os.environ.get("MUTTR_TTS_PORT", "7173"))
HOST = os.environ.get("MUTTR_TTS_HOST", "127.0.0.1")
VOICE_DIR = Path(os.environ.get("MUTTR_VOICE_DIR", Path(__file__).parent / "voices"))


class TTSBackend:
    """Wraps mlx-audio so the server stays transport-only.

    The model is loaded once at startup and reused across requests — otherwise
    generate_audio reloads weights from scratch every call, and concurrent
    reloads segfault MLX (Metal buffer races)."""

    def __init__(self, model_id: str) -> None:
        self.model_id = model_id
        self._generate = None
        self._model = None
        # Serialize inference: MLX isn't safe to call concurrently, and the
        # ThreadingHTTPServer hands requests to separate threads.
        self._lock = threading.Lock()
        self._load()

    def _load(self) -> None:
        try:
            from mlx_audio.tts.generate import generate_audio  # type: ignore
            from mlx_audio.tts.utils import load_model  # type: ignore
        except ImportError as e:
            raise RuntimeError(f"failed to import mlx_audio: {e}") from e
        self._generate = generate_audio

        # Log the actual signature so kwarg mismatches are obvious.
        try:
            sig = inspect.signature(generate_audio)
            print(
                f"muttr-tts: generate_audio params: {list(sig.parameters)}",
                file=sys.stderr,
            )
            self._accepts_kwargs = any(
                p.kind is inspect.Parameter.VAR_KEYWORD for p in sig.parameters.values()
            )
            self._param_names = set(sig.parameters)
        except (TypeError, ValueError):
            self._accepts_kwargs = True
            self._param_names = set()

        # Eagerly load weights so the first synth request is fast and so we
        # never race on concurrent loads.
        print(f"muttr-tts: loading weights for {self.model_id} …", file=sys.stderr)
        self._model = load_model(self.model_id)
        print("muttr-tts: model ready", file=sys.stderr)

    def synthesize(
        self,
        text: str,
        voice: Optional[str],
        urgency: int,
    ) -> bytes:
        assert self._generate is not None
        # Map urgency 1..4 -> expressiveness / exaggeration hint.
        # Conservative range; models ignore unknown kwargs.
        expressive = {1: 0.25, 2: 0.45, 3: 0.65, 4: 0.85}.get(urgency, 0.45)

        ref_clip, preset_name = self._resolve_voice(voice)

        with tempfile.TemporaryDirectory() as tmp:
            prefix = str(Path(tmp) / "muttr_out")
            candidates: dict[str, Any] = {
                # Pass the loaded model instance, NOT a string — avoids reloads.
                "model": self._model,
                "text": text,
                "file_prefix": prefix,
                "audio_format": "wav",
                "verbose": False,
                "play": False,
                "exaggeration": expressive,
            }
            # Voice cloning via reference clip takes priority; else preset name.
            if ref_clip is not None:
                candidates["ref_audio"] = ref_clip
                # If a transcript companion file exists, pass it as ref_text to
                # skip the Whisper STT auto-transcribe step (saves ~1.5GB download).
                txt_path = Path(ref_clip).with_suffix(".txt")
                if txt_path.is_file():
                    candidates["ref_text"] = txt_path.read_text(encoding="utf-8").strip()
                    print(
                        f"muttr-tts: ref_audio={ref_clip} ref_text_source={txt_path}",
                        file=sys.stderr,
                    )
                else:
                    print(
                        f"muttr-tts: ref_audio={ref_clip} no companion .txt at {txt_path}",
                        file=sys.stderr,
                    )
            elif preset_name is not None:
                candidates["voice"] = preset_name

            kwargs = self._filter_kwargs(candidates)
            # Show what actually reaches generate_audio (keys only).
            print(
                f"muttr-tts: generate_audio kwargs = {sorted(kwargs)}",
                file=sys.stderr,
            )
            # Serialize inference — MLX isn't reentrant.
            with self._lock:
                try:
                    self._generate(**kwargs)
                except TypeError as e:
                    kwargs.pop("exaggeration", None)
                    try:
                        self._generate(**kwargs)
                    except TypeError:
                        raise RuntimeError(
                            f"generate_audio kwarg mismatch: {e} "
                            f"(tried {sorted(kwargs)})"
                        ) from e

            wav_path = Path(prefix + ".wav")
            if not wav_path.exists():
                matches = list(Path(tmp).glob("*.wav"))
                if matches:
                    return matches[0].read_bytes()
                raise RuntimeError(
                    f"TTS did not produce a WAV file in {tmp}. "
                    f"kwargs used: {sorted(kwargs)}"
                )
            return wav_path.read_bytes()

    def _filter_kwargs(self, candidates: dict[str, Any]) -> dict[str, Any]:
        if self._accepts_kwargs or not self._param_names:
            return candidates
        return {k: v for k, v in candidates.items() if k in self._param_names}

    def _resolve_voice(self, voice: Optional[str]) -> tuple[Optional[str], Optional[str]]:
        """Returns (ref_clip_path, preset_name). At most one is non-None."""
        if not voice:
            return (None, None)
        # Absolute/relative path to a reference clip
        p = Path(voice).expanduser()
        if p.is_file():
            return (str(p), None)
        # VOICE_DIR/<name>.wav shorthand
        candidate = VOICE_DIR / f"{voice}.wav"
        if candidate.is_file():
            return (str(candidate), None)
        # Otherwise let the model interpret the string as a preset name
        return (None, voice)

    def list_voices(self) -> list[dict]:
        """Enumerate reference clips available for cloning from VOICE_DIR."""
        VOICE_DIR.mkdir(parents=True, exist_ok=True)
        clips = []
        for wav in sorted(VOICE_DIR.glob("*.wav")):
            clips.append({
                "name": wav.stem,
                "path": str(wav),
                "kind": "reference_clip",
            })
        return clips


class Handler(BaseHTTPRequestHandler):
    backend: TTSBackend  # set on class at startup

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        sys.stderr.write("muttr-tts: " + format % args + "\n")

    def handle_one_request(self) -> None:
        # Clients (the Swift narrator) cancel requests mid-flight whenever a
        # newer segment supersedes an older one. That closes the socket under
        # us; swallow the resulting BrokenPipe/ConnectionReset silently.
        try:
            super().handle_one_request()
        except (BrokenPipeError, ConnectionResetError):
            return

    def _safe_write(self, data: bytes) -> bool:
        try:
            self.wfile.write(data)
            return True
        except (BrokenPipeError, ConnectionResetError):
            return False

    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        try:
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
        except (BrokenPipeError, ConnectionResetError):
            return
        self._safe_write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._send_json(200, {"ok": True, "model": self.backend.model_id})
            return
        if self.path == "/voices":
            self._send_json(200, {
                "model": self.backend.model_id,
                "voice_dir": str(VOICE_DIR),
                "clips": self.backend.list_voices(),
            })
            return
        self._send_json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/synthesize":
            self._send_json(404, {"error": "not found"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            raw = self.rfile.read(length) if length > 0 else b"{}"
            req = json.loads(raw.decode("utf-8") or "{}")
            text = (req.get("text") or "").strip()
            if not text:
                self._send_json(400, {"error": "text is required"})
                return
            voice = req.get("voice")
            urgency = int(req.get("urgency") or 1)
            wav = self.backend.synthesize(text=text, voice=voice, urgency=urgency)
            try:
                self.send_response(200)
                self.send_header("Content-Type", "audio/wav")
                self.send_header("Content-Length", str(len(wav)))
                self.end_headers()
            except (BrokenPipeError, ConnectionResetError):
                return
            self._safe_write(wav)
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception as exc:  # noqa: BLE001
            traceback.print_exc(file=sys.stderr)
            self._send_json(500, {"error": str(exc)})


def main() -> int:
    print(f"muttr-tts: loading {MODEL_ID} …", file=sys.stderr)
    try:
        backend = TTSBackend(MODEL_ID)
    except Exception as exc:  # noqa: BLE001
        print(f"muttr-tts: failed to load model: {exc}", file=sys.stderr)
        return 1
    Handler.backend = backend
    print(f"muttr-tts: listening on http://{HOST}:{PORT}", file=sys.stderr)
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
