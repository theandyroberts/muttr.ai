# Muttr.ai — Handoff Document v2.0

**Date:** March 1, 2026  
**Launch:** March 16–17, 2026 (Silicon Valley conference — real users downloading, not a demo)  
**Website:** muttr.ai

---

## What We're Building

Muttr is a macOS app that narrates what's happening on your screen — specifically aimed at developers watching AI coding tools (Claude Code, Cursor, etc.) work. One voice, slightly detached tone, like a developer muttering about their own work. Voice escalates when something needs your attention.

Voice is the primary interface. The user isn't watching. Emphasis is the alert system — tone shift means look up.

---

## Business Model

### Pricing

| Plan | Price | Billing |
|------|-------|---------|
| Free | $0 | — |
| Pro Monthly | $7.99/month | Recurring |
| Pro Annual | $72/year ($6/month effective) | Recurring (25% savings) |

14-day Pro trial on signup. After trial, user drops to Free. Narration keeps working on the default local model — no feature cliff, just reduced quality and convenience.

### Unit Economics

| Metric | Free User | Pro User |
|--------|-----------|----------|
| Revenue | $0 | $7.99/mo or $6/mo annual |
| Your API cost | $0 | $0 (BYOK — user's own key) |
| Infrastructure | ~$0.10 (telemetry/auth) | ~$0.20 (telemetry/auth/insights) |
| Gross margin | N/A | ~97% minus Stripe fees |

---

## Tier Structure

| Feature | Free | Pro ($7.99/mo · $72/yr) |
|---------|------|-------------------------|
| Narration engine | Default local model | Choice of local models + BYOK cloud |
| Model selection | No (bundled default) | Yes (download/swap via Ollama) |
| Cloud narration | No | Yes (user's own API key) |
| Voices | 4 | Full library |
| Dispatch OUT | No | Yes (bot-to-bot events) |
| Insights | No | Daily/weekly |
| Voice commands | No | Coming soon |
| Your marginal cost | $0 | $0 |
| User's API cost | $0 | Their key, their cost |

---

## Feature List for March 16

### Core (All Tiers)

- macOS app with menu bar presence
- Professional installer (.dmg)
- Screen capture at 1–2 fps
- OCR text extraction (Apple Vision framework)
- Text diffing between frames to detect changes
- Local LLM narration with urgency levels 1–4
- TTS output with emphasis variation based on urgency
- Hotkey start/stop (default ⌘⇧M)
- User accounts (email-based)
- 14-day Pro trial, then downgrade to Free
- Telemetry to backend (session duration, narration count, urgency events)

### Setup & Permissions (First-Run Wizard)

1. Welcome screen + account creation / sign in — **simultaneously kick off model download in background**
2. Screen recording permission — download continues
3. Microphone permission (for future voice commands) — download continues
4. Accessibility permission (for future action execution) — download continues
5. Audio output device selection — download likely 60–80% done by now
6. Voice selection (4 voices Free, full library for Pro trial) — if download still running, show progress bar here
7. Quick test: capture current screen, generate narration, play it — user hears Muttr work instantly
8. Start on boot option

Key insight: the permissions flow takes 2–3 minutes of user interaction. A 2 GB model download on a 50+ Mbps connection finishes in that time. The user never feels like they're waiting for a download.

**Edge cases:**
- Slow connection: show progress at step 6 with friendly message — "Your narration engine is almost ready. Muttr works completely offline after this."
- No internet: inform user they need connectivity for initial setup. Pro users with BYOK can start with cloud narration immediately.
- Download fails: Ollama model pull is resumable. Next launch picks up where it left off.

### Pro Features (Launch)

- **Model choice:** Download and swap between local models (Llama 3.2, Kimi, MiniMax, Qwen, Mistral, Phi) via in-app model management UI
- **BYOK cloud narration:** User enters their own OpenAI or Anthropic API key. Keys stored in local Keychain only — never sent to Muttr backend. Narration router offers local, cloud, or hybrid mode when a key is present.
- **Full voice library:** All available TTS voices
- **Dispatch OUT:** Muttr emits structured events to external systems for bot-to-bot communication
- **Insights:** Daily/weekly summaries of coding activity, patterns, and productivity signals

### Pro Features (Coming Soon — Post-Launch)

- **Voice commands** with "Hey Muttr" wake word:
  - "What just happened" — summarize last 1–2 minutes
  - "Repeat that" — replay last narration
  - "I'm going down the hall" — reduce verbosity, queue summary
  - "I'm back" — catch me up, resume normal
  - Volume up/down
- **Dispatch IN:** External systems send responses back to Muttr
- **Action execution:** Muttr types keystrokes / clicks buttons based on Dispatch responses

---

## Technical Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Muttr macOS App                        │
├──────────────────────────────────────────────────────────┤
│  Screen Capture (ScreenCaptureKit)                       │
│       ↓                                                  │
│  OCR (Apple Vision Framework)                            │
│       ↓                                                  │
│  Text Diff Engine (detect what changed)                  │
│       ↓                                                  │
│  Narration Router                                        │
│       ┌───────────────────────────┐                      │
│       ↓                           ↓                      │
│  Local LLM (Ollama)        Cloud API (BYOK)              │
│  [FREE + PRO]              [PRO only]                    │
│       └───────────────────────────┘                      │
│       ↓                                                  │
│  TTS Engine (Local — Piper/Sherpa-onnx)                  │
│       ↓                                                  │
│  Audio Output                                            │
└──────────────────────────────────────────────────────────┘
                          ↕
┌──────────────────────────────────────────────────────────┐
│                    Muttr Backend                          │
├──────────────────────────────────────────────────────────┤
│  Auth & Accounts                                         │
│  License Management (trial tracking, tier enforcement)   │
│  Usage Telemetry                                         │
│  Insights Generation (daily/weekly — Pro)                │
│  Dispatch OUT relay (Pro)                                │
└──────────────────────────────────────────────────────────┘
```

### Narration Router Logic

1. Check user tier (Free or Pro)
2. If Free → always route to local LLM (default bundled model)
3. If Pro + no BYOK key → route to user's selected local model
4. If Pro + BYOK key + user chose cloud → route to cloud API
5. If Pro + BYOK key + user chose hybrid → local for urgency 1–2, cloud for urgency 3–4
6. If cloud fails/times out (>3s) → fall back to local, subtle audio cue
7. Never silence — if any engine fails, the next one picks up

### Urgency Pre-Classification (for Hybrid Mode)

Before routing to cloud, a fast local heuristic classifies urgency:
- **Pattern match for urgency 3–4:** error keywords, warning patterns, input prompts, permission requests, build failures
- **Everything else:** urgency 1–2, stays local
- The cloud model then provides the final narration and may reclassify urgency

---

## Recommended Stack

| Component | Technology |
|-----------|------------|
| App framework | Swift + SwiftUI (native macOS) |
| Screen capture | ScreenCaptureKit (macOS 13+) |
| OCR | Apple Vision Framework |
| Local LLM runtime | Ollama (bundled, Apple Silicon native) |
| Default narration model | Test during Week 1: Apple Foundation Models → Llama 3.2 3B → Phi-3 Mini → Qwen2.5 3B |
| Pro local models | User choice via Ollama: Llama, Kimi, MiniMax, Qwen, Mistral, Phi |
| Cloud narration (Pro BYOK) | OpenAI API and/or Anthropic Claude API (user's key) |
| TTS engine | Piper or Sherpa-onnx (local only, no cloud TTS) |
| Wake word (coming soon) | Picovoice Porcupine (local, custom "Muttr") |
| Speech-to-text (coming soon) | Apple Speech Framework or Whisper.cpp |
| Backend | Supabase (auth, database, telemetry) |
| Payments | Stripe (monthly + annual subscriptions) |

### Default Local Model Selection (Week 1 Decision)

Test in this priority order:

1. **Apple Foundation Models (macOS 15+):** Zero download, zero RAM overhead, native Metal. If quality is sufficient for constrained narration prompts, this eliminates the Ollama dependency entirely for the default experience. Downside: requires macOS 15, less prompt flexibility.
2. **Llama 3.2 3B (Q4_K_M):** ~2 GB download, ~3–4 GB RAM. Good general quality, runs well on Apple Silicon. The safe choice.
3. **Phi-3 Mini 3.8B:** Similar profile to Llama 3.2. May be better at structured JSON output.
4. **Qwen2.5 3B:** Strong alternative, good with code-related content.

Decision criteria: narration quality, latency on M1 (baseline hardware), memory footprint, consistency of JSON output format.

---

## The Voice Persona

Single voice. Semi-disinterested developer narrating their own work. Slightly accented. Not performative, not robotic. The tone of someone who's seen a lot of code scroll by.

### Urgency Levels

| Level | Tone | Example |
|-------|------|---------|
| 1 - Routine | Calm, almost monotone | "Opening config.ts… updating the connection string." |
| 2 - Interesting | Slightly engaged | "Hm, refactoring the auth middleware." |
| 3 - Noteworthy | Alert, emphasis | "Error in the build. Type mismatch on line 47." |
| 4 - Needs Input | Urgent, distinct | "It's asking for the API key. Needs your input." |

The shift in emphasis is the signal. When tone changes, user looks up.

### What Gets Narrated

- **Always:** File opens/closes, errors, warnings, input requests, major structural changes
- **Summarized:** Routine edits, scrolling
- **Never:** Character-by-character typing, unchanged content, meaningless UI chrome

---

## Narration Prompt

The same prompt template works for both local and cloud models. The constrained output format is key to getting good results from smaller models:

```
You are Muttr, a developer narrating screen activity.
Given this screen diff, produce a brief spoken narration.

Rules:
- One sentence, max 20 words
- Speak as a slightly bored developer muttering to themselves
- Assign urgency: 1=routine, 2=interesting, 3=noteworthy, 4=needs input
- Output JSON only: {"narration": "...", "urgency": N}

Diff:
[inserted diff content]
```

---

## BYOK (Bring Your Own Key) Implementation

### User Flow

1. In Pro settings → "Cloud Narration (Optional)"
2. User selects provider: OpenAI or Anthropic
3. User pastes API key
4. App validates key with a test request
5. User chooses mode: Local Only / Cloud Only / Hybrid
6. Key stored in macOS Keychain — never transmitted to Muttr backend

### Supported Providers

| Provider | Models | API Format |
|----------|--------|------------|
| Anthropic | Claude Haiku, Claude Sonnet | Anthropic Messages API |
| OpenAI | GPT-4o-mini, GPT-4o | OpenAI Chat Completions API |

The narration prompt is identical across providers. The router just changes the endpoint and request format.

### Hybrid Mode (BYOK)

When hybrid is selected and a BYOK key is present:
- Urgency 1–2 diffs → local model (free, fast)
- Urgency 3–4 diffs → cloud API via user's key (better quality where it matters)
- Cloud timeout/failure → automatic local fallback

---

## Dispatch OUT (Pro — Launch Feature)

Muttr emits structured events to external systems. This is bot-to-bot communication — Muttr is the messenger, not the authority.

### Event Format

```json
{
  "event": "narration",
  "timestamp": "2026-03-16T14:30:00Z",
  "narration": "It's asking for the API key. Needs your input.",
  "urgency": 4,
  "diff_summary": "Terminal prompt: 'Enter ANTHROPIC_API_KEY:'",
  "session_id": "abc-123"
}
```

### Configuration

- Pro users configure webhook URL(s) in settings
- Events sent via HTTP POST
- Optional filtering: send only urgency >= N
- Optional: send all events or only specific types (errors, input requests, etc.)

### Future (Post-Launch)

- **Dispatch IN:** External systems send responses back
- **Action execution:** Muttr types keystrokes / clicks buttons based on Dispatch responses
- Example flow: Claude Code asks "can I continue?" → Muttr detects, dispatches → Supervisor bot responds "approved" → Muttr types "yes"

---

## Insights (Pro — Launch Feature)

Daily and weekly summaries of coding activity generated from narration history.

- Total active narration time
- Urgency distribution (how many errors, input requests, etc.)
- Most-edited files
- Session patterns (when you code, how long, peak error times)
- Stored locally, optionally synced to backend for cross-device access

---

## System Requirements

| Requirement | Minimum | Recommended |
|-------------|---------|-------------|
| macOS | 13 (Ventura) | 14+ (Sonoma) |
| Processor | Apple M1 | Apple M2 or later |
| RAM | 8 GB | 16 GB |
| Disk | 3 GB (app + model + TTS voices) | 5 GB |
| Internet | Initial setup only (Free) | For BYOK cloud narration (Pro) |

**Intel Macs:** Not supported for local narration. The app will detect non-Apple-Silicon hardware and inform the user. If they have a Pro subscription with BYOK, cloud-only narration is available as an alternative.

---

## Performance Budget

| Pipeline Stage | Target | Local | Cloud (BYOK) |
|----------------|--------|-------|---------------|
| Screen capture | < 50ms | 50ms | 50ms |
| OCR | < 200ms | 150ms | 150ms |
| Diff computation | < 50ms | 20ms | 20ms |
| LLM narration | < 2s | 500ms–1.5s | 1–3s |
| TTS synthesis | < 500ms | 300ms | 300ms |
| **Total end-to-end** | **< 3s ideal** | **~1–2.5s** | **~1.5–4s** |

Note: Local narration is likely faster than cloud due to no network round trip. Free users may get lower latency than BYOK cloud users.

---

## Two-Week Sprint

### Week 1: March 3–9 — Core Pipeline + Local LLM

- **Day 1–2:** Screen capture (ScreenCaptureKit) + OCR (Apple Vision) pipeline working end-to-end
- **Day 2–3:** Text diff engine. Test Apple Foundation Models for narration quality. If insufficient, integrate Ollama + Llama 3.2 3B
- **Day 3–4:** Narration router logic. BYOK cloud integration (Anthropic + OpenAI endpoints)
- **Day 4–5:** TTS integration (Piper/Sherpa-onnx) with urgency-based emphasis variation
- **Day 5–6:** End-to-end testing against screen recordings. Latency profiling on M1 baseline
- **Day 6–7:** Narration prompt tuning. Compare local vs cloud quality. Iterate prompt for best local results. Decide default model.

### Week 2: March 10–15 — App Shell + Polish

- **Day 8–9:** Menu bar app (SwiftUI), settings panel, hotkey (⌘⇧M), model management UI
- **Day 9–10:** First-run wizard: permissions flow with background model download, voice selection, quick test
- **Day 10–11:** Account/auth (Supabase), Stripe integration (monthly + annual), trial logic, tier enforcement
- **Day 11–12:** BYOK settings UI, key validation, mode selection (local/cloud/hybrid). Dispatch OUT webhook configuration and event emission
- **Day 12–13:** DMG installer, code signing, notarization, clean-machine testing
- **Day 13–14:** Telemetry integration, Insights data collection, final QA, 30-minute stability tests
- **Day 14:** Demo prep, backup plan for conference Wi-Fi issues (local-first = advantage here)

### March 16–17: Launch

Live at Silicon Valley conference. Real users installing from muttr.ai.

---

## Key Design Principles

1. **Voice is the primary interface** — user isn't watching, shouldn't need to click
2. **Emphasis is the alert system** — tone shift means look up
3. **Local-first, always** — narration works without internet, cloud is an enhancement
4. **Muttr is smart but not the authority** — interprets and communicates, doesn't decide
5. **Bot-to-bot is first class** — Dispatch system treats other bots as peers
6. **Zero marginal cost** — free tier costs you nothing, Pro tier costs you nothing (BYOK)

---

## Success Criteria for March 16

- [ ] Installs cleanly on macOS 13+ (Apple Silicon)
- [ ] Permissions flow works smoothly with background model download
- [ ] Account creation works
- [ ] Voice selection works (4 Free, full library Pro)
- [ ] Local narration runs stable 30+ minutes
- [ ] Urgency emphasis clearly audible across all 4 levels
- [ ] Hotkey start/stop works
- [ ] BYOK key entry, validation, and cloud narration works
- [ ] Hybrid mode routes correctly (local for 1–2, cloud for 3–4)
- [ ] Dispatch OUT emits events to configured webhook
- [ ] Trial tracking works (14-day Pro trial)
- [ ] Free tier limits enforced after trial
- [ ] Telemetry flowing to backend
- [ ] Insights data collecting (display can be basic for launch)

---

## Open Questions for Development

| # | Question | Recommendation |
|---|----------|----------------|
| 1 | Apple Foundation Models vs Ollama for default? | Test Apple first (zero download). Fall back to Ollama if quality insufficient. |
| 2 | Bundle Ollama or require user install? | Bundle. First-run friction kills adoption. |
| 3 | Which default local model? | Test Llama 3.2 3B, Phi-3 Mini, Qwen2.5 during Week 1. |
| 4 | TTS engine? | Test Piper vs Sherpa-onnx for quality and footprint. |
| 5 | Intel Mac support? | Cloud-only via BYOK for Pro users. No free tier on Intel. |
| 6 | Model update strategy? | App checks for recommended models on launch. Manual download. |
| 7 | Latency budget? | Under 3s ideal, under 5s acceptable. |

---

## Risk Mitigation

- **Local model quality too low:** If 3B models can't produce usable narrations in Week 1, try 7B (higher memory, works on 16 GB Macs). Worst case: require BYOK for good narration, local becomes "basic mode."
- **Ollama bundling issues:** If .dmg signing/notarization problems arise, pivot to one-click Ollama installer. Test during Week 1.
- **Memory pressure on 8 GB Macs:** Profile aggressively. Implement model unloading when narration is paused. Ollama supports this natively.
- **Conference Wi-Fi unreliable:** Local-first architecture is the advantage. Demo machines should have models pre-downloaded. Free tier demo needs zero internet.
- **Apple Foundation Models not available:** Only on macOS 15+. If targeting macOS 13+, Ollama is the safe default.

---

## Assets & Context

- **Screen recordings:** Andy has test recordings of AI coding sessions for development iteration and regression testing. Deterministic inputs — run the same recording through the pipeline to compare output quality.
- **Domain:** muttr.ai

---

## Contact

Andy is the product owner. This document reflects conversations through March 1, 2026.

*This document (v2.0) supersedes the original handoff document. Key changes: local-first narration architecture, BYOK instead of Muttr-paid API costs, revised pricing ($7.99/mo, $72/yr), Dispatch OUT as launch Pro feature, voice commands moved to post-launch, Recaps renamed to Insights.*
