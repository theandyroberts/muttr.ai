# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Muttr is a macOS app that narrates what's happening on your screen using AI. Aimed at developers watching AI coding tools (Claude Code, Cursor, etc.) work. Voice is the primary interface — emphasis shifts signal urgency.

**Launch:** March 16-17, 2026 at a Silicon Valley conference (real users, not a demo).

## Technology Stack

| Component | Technology |
|-----------|------------|
| App framework | Swift + SwiftUI (native macOS, menu bar app) |
| Screen capture | ScreenCaptureKit (macOS 13+) |
| OCR | Apple Vision Framework |
| Local LLM | Ollama (bundled, Apple Silicon native) |
| Cloud narration (Pro) | OpenAI + Anthropic APIs (BYOK — user's own keys) |
| TTS | Piper or Sherpa-onnx (local only) |
| Backend | Supabase (auth, database, telemetry) |
| Payments | Stripe (monthly $7.99 + annual $72) |

## Core Architecture

The processing pipeline runs in this order:

```
Screen Capture (ScreenCaptureKit, 1-2 fps)
    → OCR (Apple Vision)
    → Text Diff (detect what changed)
    → Narration Router (selects local or cloud LLM)
    → TTS (urgency-based emphasis)
    → Audio Output
```

### Narration Router Logic

- Free tier → always local LLM (bundled default model)
- Pro + no BYOK key → user's selected local model (via Ollama)
- Pro + BYOK + cloud mode → cloud API (OpenAI or Anthropic)
- Pro + BYOK + hybrid mode → local for urgency 1-2, cloud for urgency 3-4
- Cloud timeout (>3s) → automatic local fallback
- Never silence — if any engine fails, the next one picks up

### Urgency Levels

| Level | Meaning | TTS Behavior |
|-------|---------|--------------|
| 1 | Routine | Calm, monotone |
| 2 | Interesting | Slightly engaged |
| 3 | Noteworthy | Alert, emphasis |
| 4 | Needs input | Urgent, distinct |

### Narration Output Format

All LLM responses (local and cloud) must return JSON:
```json
{"narration": "...", "urgency": N}
```
Narrations are one sentence, max 20 words, in the voice of a slightly bored developer muttering to themselves.

## Tier System

- **Free:** Default local model only, 4 voices, no model choice, no Dispatch/Insights
- **Pro:** Model selection via Ollama, BYOK cloud narration, full voice library, Dispatch OUT webhooks, daily/weekly Insights
- 14-day Pro trial on signup, then auto-downgrade to Free

## BYOK Implementation

API keys are stored in macOS Keychain only — never sent to Muttr backend. Keys are validated with a test request on entry. Cloud requests go directly from user's machine to the provider.

## Performance Budget

| Stage | Target |
|-------|--------|
| Screen capture | < 50ms |
| OCR | < 200ms |
| Diff computation | < 50ms |
| LLM narration | < 2s |
| TTS synthesis | < 500ms |
| **Total end-to-end** | **< 3s ideal, < 5s acceptable** |

## System Requirements

- macOS 13+ (Ventura), recommended 14+ (Sonoma)
- Apple Silicon required for local narration (M1 minimum, M2+ recommended)
- 8 GB RAM minimum, 16 GB recommended
- Intel Macs: cloud-only via BYOK Pro subscription (no Free tier)

## Design Principles

1. Voice is the primary interface — user isn't watching
2. Emphasis is the alert system — tone shift means look up
3. Local-first, always — internet optional, cloud is enhancement
4. Muttr is smart but not the authority — interprets, doesn't decide
5. Bot-to-bot is first class — Dispatch system treats other bots as peers
6. Zero marginal cost — Free costs nothing to operate, Pro uses BYOK

## Reference

Full product specification is in `muttr_handoff_v2.md`.
