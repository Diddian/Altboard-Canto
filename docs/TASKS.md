# Altboard-Canto development tasks

**Active development branch: `main`.** Read GitHub HEAD before implementation;
the historical merge base is not a current development baseline.
Use only `.github/workflows/build-unsigned-ipa.yml` on `main` for unsigned
SideStore IPAs. Latest verified successful development IPA as of 2026-11-10:
#171 (`af05cf6f`). Build #172 (`230bdbd`) failed a Settings source test;
#173 (`3218541`) failed SwiftUI Slider compilation. Both source repairs
are included in the next development build. Physical iPhone acceptance is pending.

**Historical caution:** Older task descriptions below mention temporary feature
branches and a custom Emoji catalog. They are archival notes, not current
instructions. The native iOS keyboard picker is retained; the project's Emoji
glyph is only the button icon. Do not merge obsolete QA branches or revive
the retired catalog without a new reviewed request.

GitHub Issues are disabled in this repository (GitHub API 410). This file is
the versioned task board until Issues are enabled.

Statuses: [x] code implemented in source; [ ] pending / requires verification.
Neither a checkbox nor an IPA build demonstrates physical iPhone acceptance.
When reporting progress, give the scope and numerator/denominator; do not
conflate source implementation, passing CI, and device acceptance.

**Verification gates:** Pre-build source checks, exact-SHA iOS compilation
and packaging, and physical-device acceptance are separate gates.
T-022.4/T-022.10, T-023.8, and T-024.14/T-024.15 require physical iPhone
evidence; T-024.13 requires a successful IPA build. Keep their original
checklist entries open until verified. A passing pre-build suite is not
90% completion of these full workstreams.

**Current workstream ownership (no duplicate implementation owners):**
- `T-024`: consolidated app/Settings/audio repairs; gated by CI and device QA.
- `T-023`: remaining cross-functional audits; exclude repairs already in T-024.
- `T-022`: model performance measurements and alternative backend evaluation.
- `T-019`: experimental incremental keyboard dictation, after T-022 safety evidence.
- `T-020`: meeting capture/finalization; T-024 fixes are prerequisites.
- `T-021`: active swipe and native Globe/Emoji follow-up; earlier T-016 is historical.
- `T-007`: historical meeting-transcription plan; T-020 owns current development.
- `T-001–T-018`: legacy feature and iPhone-acceptance history, not replacement
  instructions for current owners. Cross-reference their still-open device issues.

## T-024 - Consolidated mainline implementation batch (2026-11-10)

**Goal:** accumulate independently reviewable fixes and regression checks before
the *next single* unsigned IPA build. The approved baseline is successful
development IPA #171 at `af05cf6f`. Avoid incremental workflow triggers,
new workflows, parallel branches and claims of completed device QA.

### Completed in source for this batch; CI and iPhone verification pending

- [x] T-024.1 Fix partial `BackgroundAudioSession.startSession()` failure
  rollback: stop a started engine, remove an attempted tap, release an activated
  AVAudioSession, reset shared state, and rethrow. Preserve a preexisting active
  session. Owner: `Sayboard/Services/BackgroundAudioSession.swift`.
- [x] T-024.2 Fail explicitly if 16 kHz microphone conversion cannot be
  configured. Propagate errors through the single existing capture owner;
  stop only sessions started by the failed dictation request.
- [x] T-024.3 Make a failed dictation history audio-file open a visible
  diagnostic fallback while preserving transcription; release an unread
  accumulator when final recognition owns a copied segment. Bound waveform
  envelope storage and use written frame counts for recording duration.
- [x] T-024.4 On failed meeting start, delete temporary audio and directory,
  release the newly started session, reset coordinator pointers, and avoid
  advancing meeting sequence numbers for aborted capture.
- [x] T-024.5 Process an unrecognized meeting audio backlog in bounded
  eight-second finalization chunks rather than one unbounded allocation.
  Preserve saved audio and mark failed decoding as a partial transcript;
  never label incomplete transcription as successful.
  Rotate audio writers atomically, reject overlapping dictation finalization,
  stop meeting capture on audio interruption, and preserve manifest-save errors.
- [x] T-024.6 Show semantic VoiceOver labels and sufficient tappable areas for
  meeting playback/seek/delete, honor Reduce Motion during row expansion,
  identify partial transcript state, and report rename/delete/save failures.
- [x] T-024.7 Make the Speech Models filter reset discoverable and accessible.
  Route the existing "Open Models" setup banner and models deep link to
  the Speech Models destination rather than only switching tabs.
- [x] T-024.8 Add an explicit, cancel-safe output-language-code editor;
  do not overwrite a valid existing output-language choice with an empty
  or invalid custom-language selection.
- [x] T-024.9 Expose existing persisted haptic intensity and Reset to default
  within Keyboard settings, without creating a second haptic engine.
- [x] T-024.10 Confirm compiled model-cache deletion and keep the export share
  sheet's temporary file until the share sheet dismisses.
- [x] T-024.11 Respect Reduce Motion and stop continuous keyboard loading and
  microphone pulse animations when their views disappear; honor Reduce Motion
  in the Settings keyboard layout preview.
- [x] T-024.12 Add bounded source regression checks to the existing
  `scripts/test_settings_contract.py` and
  `scripts/test_keyboard_safety_contract.py`; no new test framework.
- [ ] T-024.13 Check source tests, Xcode compilation, IPA packaging and exact
  commit SHA using the **one existing main-branch unsigned IPA workflow**.
  Run #172 failed in a stale button-label test. Run #173 passed that step but
  failed iOS compilation: the haptic Slider must use a trailing label closure.
  The Slider initializer and stale finalization assertions are repaired.
  Verify the new request-cancellation and bounded-waveform Swift checks before
  compilation. Mark verified only after the exact-SHA build succeeds.
- [ ] T-024.14 Physical iPhone acceptance: microphone permission/recording
  start failures and recovery; original vs new Active Session; 15-minute
  meeting rollover and Stop; saved audio after interrupted/partial ASR;
  EN/DE/Yue typing and dictation; model navigation; haptic reset; VoiceOver;
  Reduced Motion, cancellation and no blank keyboard.
- [ ] T-024.15 Measure real-device memory for long recording and Qwen3
  decode backlog before claiming improvement. Source-side preparations cap
  meeting transcription backlog to two minutes, flag skipped transcription
  segments, and keep full audio in separately written CAF files. Recorder
  write failures are surfaced; the stream can still lose audio if disk IO
  fails. Real memory, capture fidelity and 2-hour recovery remain UNTESTED.
  Full recovery after process termination still requires a resumable
  saved-audio pipeline, not an unbounded in-memory loop.

The source-level review spans release, UX, accessibility, audio reliability,
data integrity, architecture and regression coverage. It is not an independent
multi-agent review. Retain the last usable IPA until a new device acceptance.

## P0-P2 - Cross-functional app audit and optimization (T-023, 2026-11-10)

**Source baseline:** main at `1e7befac`; unsigned IPA #170 succeeded.
This is a source-based first audit across Settings, keyboard, onboarding, model
and audio boundaries, not a rendered UI or physical-device certification.
Review lenses: UX/motion, frontend, accessibility, animation performance,
integration, backend, security/privacy, data integrity, performance,
AI efficiency, QA, test automation, technical/linguistic source research,
documentation and release. The existing app owns every implementation; no
new server, duplicate keyboard coordinator, animation engine or model dependency.

### P0 - Settings and onboarding: first bounded implementation

- [x] T-023.1 Establish main SHA, source owners, current Settings navigation
  contract, run #170 and the active task board; read routed project sources.
- [x] T-023.2 Show low-storage warning based on `DiskSpace.isLow()` regardless
  of iOS 27 Neural Engine policy. Owner: `Sayboard/Views/SettingsView.swift`.
- [x] T-023.3 Show a recoverable error when Active Session activation throws;
  record existing speech failure diagnostic rather than swallowing the error.
  Owner: `Sayboard/Views/SettingsNavigationViews.swift`.
- [x] T-023.4 Display Auto-capitalization and Double-Space Period only for
  Alphabet; preserve persisted preferences when switching layouts. Show
  haptic-off feedback in the interactive preview.
- [x] T-023.5 Preserve VoiceOver navigation within the preview and use semantic
  labels for icon keys instead of SF Symbol identifiers. No new touch owner.
- [x] T-023.6 Respect Reduce Motion during onboarding's directional transition
  and avoid delaying navigation when animation is disabled.
- [x] T-023.7 Verify existing `scripts/test_settings_contract.py` contracts,
  Xcode compilation and exact-SHA unsigned IPA through the single workflow.
  Workflow #171 succeeded for `af05cf6f` (source before T-024).
  These checks do not certify new T-024 code or physical-device behavior.
- [ ] T-023.8 Verify affected Settings/preview/onboarding states on an iPhone:
  low disk warning, denied microphone, keyboard layouts, haptic off/on,
  VoiceOver, Dynamic Type and Reduce Motion.

### P0/P1 - Remaining code and interaction audits

- [ ] T-023.9 Keyboard startup/switching: trace UIKit controller ownership,
  host focus, extension relaunch, app/keyboard App Group handshake and the
  historical blank drawing board. Correlate `KeyboardLifecycleTrace` and
  physical-device evidence before replacing loading logic.
- [x] T-023.10 Source review of audio lifecycle complete: session activation
  rollback, tap/converter setup, interruption, restart and audio-writer error
  paths were traced; a separate write-failure flag is prepared.
  Deterministic tests exist, but latest edits are NOT compiled or iPhone-tested.
  Preserve one tap; T-024.14 owns runtime acceptance.
- [ ] T-023.11 Source mitigation prepared: cap only the *transcription* FIFO,
  detect overflow and mark transcript incomplete, while retaining disk-backed
  meeting audio. Peak memory, disk backpressure and 1.7B decoding on a real
  iPhone are not measured. Do not claim a verified speed or fidelity gain.
- [x] T-023.12 Source audit: `MainTabView` uses native `TabView` without
  instantiating `TabBarTapInterceptor`. The old seven-tap coordinator is
  retained as an unused source file, not an active navigation owner.
  It is not evidence of a duplicate live gesture; runtime inspection remains
  part of T-023.8 and T-024.14.
- [ ] T-023.13 Settings UX/a11y: validate nested Speech & AI disclosures,
  Voice Output custom-language code/error feedback, AI availability,
  model downloads, keyboard previews and Diagnostics with long EN/DE/zh-Hant
  labels, larger text and VoiceOver; preserve saved settings.
- [ ] T-023.14 Storage and privacy: verify atomic export/delete/recovery
  across voice notes, meeting parts, corrections and models, interrupted
  operations, App Group permissions and private metadata. No transcript,
  host input, swipe path or raw audio in feature diagnostics.
- [ ] T-023.15 Motion/performance: audit long-running keyboard microphone
  animations, reduced-motion paths, offscreen cancellation, layout stability,
  touch latency and repeated observers. Use existing SwiftUI/UIKit primitives;
  Raea is not a keyboard UI dependency.
- [ ] T-023.16 Language/IME and suggestions: reuse T-012, T-013 and T-021;
  measure Cantonese mixed romanization and EN/DE candidates against current
  dictionaries before changing ranking or introducing another decoder.
- [ ] T-023.17 Speech models and technical research: reuse T-022 and T-019;
  compare measured Parakeet v3/Core ML, Whisper, Moonshine and Qwen3 to
  Meetily's desktop strategies. No unverified 4x claim or new ONNX default.
- [ ] T-023.18 Quality/release: strengthen affected deterministic policy
  tests, inspect actual CI jobs and artifact metadata, and keep a known usable
  SideStore IPA until new device acceptance. Do not equate green CI with QA.
- [x] T-023.19 Reconciled the existing Settings map:
  `docs/APP-STRUCTURE.json` and its generated menu now include haptic
  strength/reset, the confirmed custom-language editor and model-cache
  confirmation. Previous installed-device baseline remains historical;
  the current source still requires iPhone visual acceptance. No new tracker.

## T-022 - Mainline performance and reliability optimization (Meetily review, 2026-11-10)

Goal: improve measured iPhone dictation latency, recording throughput, keyboard
responsiveness and recovery without changing default model selection or removing
Cantonese, keyboard accessibility, App Group state or offline operation.
Meetily's claimed 4x speedup has no equivalent iPhone baseline. Its desktop
GPU/Flash-Attention configuration is not directly portable to iOS. Altboard
already supports Parakeet TDT v2/v3 through FluidAudio/Core ML.
The current iOS 27 CPU fallback must not be bypassed without a background-ASR
acceptance test. Keep T-019/T-021 ownership; do not create duplicate engines
or a second swipe/keyboard state machine.

- [x] T-022.1 Review Meetily v0.4.1 code (Whisper GPU backends, INT8 ONNX
  Parakeet, VAD, model reuse, worker ordering) against Altboard main at
  4915b55; record adoption constraints before adding dependencies.
- [x] T-022.2 Replace repeated front-of-array sample removal with an
  amortized FIFO queue for host-app dictation/meeting buffers. Preserve order,
  chunk offsets, single microphone tap, reset and unread audio. Add deterministic
  Swift regression coverage to the existing unsigned IPA workflow.
- [x] T-022.3 Instrument finalization, ASR decode and input-audio durations
  through existing bounded App Group FeatureDiagnostics (no audio or transcript
  payload). Versioned decode events also include an enumerated engine,
  input duration and resident memory sample; the latter is not peak memory.
  Code-level checks are not physical-device performance results.
- [ ] T-022.4 On physical iPhone measure cold/warm English and German dictation
  using existing Parakeet v3, Whisper and an identical fixed audio set: stop-to-
  insertion latency, decode latency, real-time factor, peak memory, battery
  and background acceptance. Preserve Qwen3 for Cantonese and code-switching.
- [ ] T-022.5 Only if T-022.4 shows benefit, prototype a separate opt-in
  Parakeet v3 INT8 ONNX backend with the existing sherpa-onnx package. Verify
  the exact model assets, licenses, iOS compatibility, memory and background
  behavior. Do not change the default model or silently download large assets.
- [ ] T-022.6 Evaluate speech-activity segmentation against the current audio
  path using matched English/German clips. Reject any VAD setting that loses
  quiet consonants, word boundaries, pauses or speech on Stop/Cancel.
- [ ] T-022.7 Profile keyboard activation, Globe switching, touch ownership,
  swipe decoder/brush, EN/DE suggestion latency and Cantonese SQLite lookup
  before editing their active owners. Retain current accessibility and
  keyboard extension lifecycle; resolve observed defects individually.
- [x] T-022.8 Review app/extension request ownership, recorder errors and
  bounded meeting queue. Reject cancelled or superseded inference after
  asynchronous decode/LLM work; drain capture callbacks before closing audio.
  Settings, keyboard-safety, lifecycle, symbol and IPA-validator Python
  contracts execute successfully. Pure Swift policies remain part of the
  exact-SHA CI gate; physical behavior remains T-022.10/T-024.14.
- [x] T-022.9 Verify Xcode compilation, packaged host+appex, model resources
  and one unsigned SideStore IPA from main through the existing workflow.
  Workflow #170 succeeded for SHA 1e7befac; physical device QA remains open.
  Previous usable IPA stays available; no Release Candidate label.
- [ ] T-022.10 Accept on physical iPhone only after English, German and
  Cantonese dictation, cancellation, keyboard switching, swipe and meeting
  recording pass, including long-recording memory and uninterrupted audio.

## P0 (next implementation) — Fast Live Dictation on the normal microphone (T-019)

**Status: experimental code prepared, pending Xcode and physical iPhone verification.** User-confirmed target:
the existing microphone on Altboard's normal keyboard should show recognized
speech in the active host text field while speaking, using the *already
downloaded* offline Qwen3-ASR 1.7B ONNX model. Do not mistake a recording
indicator or keyboard-only preview for working live host-field dictation.
Keep existing tap-to-stop/batch dictation as the safe fallback until iPhone QA.

- [ ] T-019.1 Benchmark current `SherpaOnnxOfflineRecognizer` on physical
  iPhone with the actual Qwen3-ASR 1.7B ONNX download: cold/warm load,
  per-chunk real-time factor, resident/peak memory, thermal throttling,
  battery and foreground/background behavior. Meeting Assistant reportedly
  achieves live ASR with the same model family; do not assume an identical
  runtime or streaming API. Confirm support in the pinned sherpa-onnx version.
- [ ] T-019.2 Reuse `BackgroundAudioSession`'s single microphone tap and
  16 kHz samples. Add a bounded streaming/chunk-decoding coordinator and
  speech-end detection. Target short (approximately 2–4 s) provisional
  windows with measured rather than assumed update latency, overlap and
  syllable/word-boundary reconciliation; do not run overlapping 1.7B decodes
  or block the real-time audio callback.
- [ ] T-019.3 Define App Group incremental transcript updates with a session
  token, monotonically increasing revision, stable text, provisional tail
  and completion/cancellation status. Notify the keyboard without copying
  audio to the extension, storing raw host text, or starting a second mic.
- [ ] T-019.4 For compatible hosts, update only the current document via
  `UITextDocumentProxy.setMarkedText` with a bounded provisional tail.
  Check document identifier and local context before replacing or
  unmarking. If focus changes, the cursor moves, host access is restricted
  or marked-text support fails, fall back to read-only preview plus safe
  final insertion; never overwrite unrelated host text.
- [ ] T-019.5 On Stop, reconcile the final Qwen recognition and existing
  Cantonese normalization/voice output exactly once. No double insertion,
  lost words, unbounded partial text, or silent conflict with the existing
  AI/translation path. On Cancel, discard provisional input only when
  ownership can be verified; preserve prior user-typed text.
- [ ] T-019.6 Keep one microphone control and existing start/stop/cancel,
  Active Session, privacy, app-group and SideStore behavior. Apply first
  to the normal keyboard microphone. Other layouts may reuse it after QA.
  Honor currently selected output language; live source-language preview
  is not a promise of simultaneous live translation.
- [ ] T-019.7 Run cheapest targeted source/unit checks, then one existing
  unsigned IPA workflow from `main`. On iPhone test Yue/English/German
  code-switch, punctuation, host switching, app lock, model cold start,
  1.7B memory pressure, background interruption and Stop/Cancel. Record
  first-text and subsequent-update latency; do not promise Apple-like
  speed before the measurements meet acceptance.
- [ ] T-019.8 Enable fast live dictation by default for an eligible Qwen3
  microphone only **after** physical-iPhone acceptance. Until then the
  original proven batch behavior remains available and no user setting is
  silently discarded.

## P1 (after T-019) — Experimental Meeting Record (T-020)

**Status: experimental recorder, UI and single-meeting index prepared, default OFF; 2-hour real device QA pending.** Separate long-form recording from normal
keyboard dictation. User enables the experiment in Settings and starts one
meeting; the visible recording is continuous even when storage rolls over.

- [ ] T-020.1 Add `Settings > Dictation > Experimental > Meeting Record`
  toggle, disabled by default; clearly distinguish it from Active Session
  and the normal microphone. Display active recording, elapsed time,
  microphone privacy, Stop and interrupted/low-storage states.
- [ ] T-020.2 Keep one uninterrupted `AVAudioEngine` capture. Roll the
  underlying audio writer every **15 minutes** at a sample-accurate
  boundary: finalize a segment, start the next within the same meeting,
  **without** stopping the UI session or creating a second input tap.
  Recover partial segments on app/process interruption and show any
  actual gap; never claim uninterrupted audio where none exists.
- [ ] T-020.3 Use Qwen3-ASR 1.7B for ongoing offline transcription.
  Publish new provisional/confirmed transcript passages roughly every
  **5–10 seconds**, with chunk overlap and timestamp alignment; never
  let a slow decode block recording. Decoding can fall behind safely,
  with a visible backlog and preserved audio for recovery.
- [ ] T-020.4 Persist a single meeting ID and one manifest/index:
  meeting start/end, language/output settings, aggregate state,
  ordered audio segments, segment duration and start offset,
  transcript status and recovery markers. Store segment audio and
  per-segment transcript together under one meeting directory/record;
  use atomic manifest writes and existing secure file protection.
- [ ] T-020.5 A continuous 120-minute meeting MUST appear as **one**
  Meeting Record containing **eight 15-minute audio files**, numbered
  1–8. A partial final segment is kept for shorter/irregular lengths.
  Opening the meeting displays all audio parts and one combined,
  chronologically ordered transcript with meaningful paragraphs and
  optional timecodes; deduplicate overlapped recognition at boundaries.
- [ ] T-020.6 Grouped export/delete/retention act on the whole meeting;
  never allow the existing per-record history retention to orphan audio
  parts. Keep recordings/transcripts on-device, with no background
  listening before explicit start. Specify disk-space safety and
  crash-recovery semantics before enabling.
- [ ] T-020.7 Test rollover at 14:59, 15:00, 15:01, 30:00 and 120:00,
  exact 2-hour group count, mid-sentence boundary, Stop/Cancel, lock,
  Bluetooth/phone interruptions, 2-hour RAM/battery/thermal effects,
  low storage, partial transcription and re-open/export. Verify on
  SideStore iPhone before broadening access.

**Source-level design contract:** `docs/live-meeting-transcription-experiment.json`.
T-019 and T-020 are future implementation work; documentation here does
not certify new streaming dictation or meeting recording behavior.

## P0 — Swipe Typing long words, disappearing trail and opt-in learning (T-021)

**Experimental code prepared (2026-11-03); iPhone QA pending.** User reports that `penetrate`,
`strange` and `tight` produce no recognized word/candidates, sometimes
after crossing/revisiting the swipe path; ChatGPT accepts swipe input but the
brush trail becomes invisible after several gestures, while the app's own
keyboard test field still draws it. This issue is **not** marked fixed.

**Verified source-level cause:** All three named words are absent from
`LatinWordSuggestions.commonWords["en"]`; the current gesture decoder
passes *only* that small built-in English/German list to
`LatinSwipeDecoder.rank`. It cannot return a missing word regardless
of gesture accuracy. There is **no explicit self-intersection rejection** in
the present decoder, so whether crossings independently cause failures is
unverified. Existing `LatinSwipeSession` bounds touch points to 160;
the fixed 32-sample positional matcher and score gates may further
penalize longer, looping, irregular-speed paths. The ChatGPT-only
rendering/lifecycle regression remains unlocalized.

**External implementation review completed (read-only):**
- [JBoard](https://github.com/nkrsn/jboard) — iOS UIKit/Swift,
  MIT original code. [SwipeDecoder](https://github.com/nkrsn/jboard/blob/main/Core/SwipeDecoder.swift)
  uses frequency-aware endpoint buckets, coarse matching followed by
  banded DTW; [KeyboardView](https://github.com/nkrsn/jboard/blob/main/Keyboard/KeyboardView.swift)
  renders a `CAShapeLayer` swipe trail; physical iPhone prototype and
  synthetic long-word tests exist. Its 82,834-entry dictionary and word
  pairs have separate attribution/licenses; verify notices before reuse.
- [Ortholinear](https://github.com/IgorVaryvoda/Ortholinear) —
  iOS Swift 6, MIT original code. Its
  [GlideDecoder](https://github.com/IgorVaryvoda/Ortholinear/blob/main/Core/GlideDecoder.swift)
  scores in-order key passes, spatial/shape distance, banded elastic
  matching, frequency and context; [GlideTests](https://github.com/IgorVaryvoda/Ortholinear/blob/main/Tests/GlideTests.swift)
  cover jitter, corner cutting, timing and learned words. Existing glide
  language claims cover English/Ukrainian, not ready-made German.
- [swipeType](https://github.com/ZimengXiong/swipeType) —
  MIT Rust/macOS benchmark/reference with bounded-memory, banded DTW
  and first/last-key pruning. A whole Rust/FFI port would add complexity.
- **Do not copy:** [iSwipe](https://github.com/akemin-dayo/iSwipe)
  is GPL-3.0 and hooks the old iOS system keyboard; older `sswipe`
  research found no verified source license.

- [ ] T-021.1 Make the named `penetrate`, `strange`, `tight`,
  `it's very strange` and multiword-space cases explicit regression
  tests. Separate **missing vocabulary**, **gesture not completed**,
  **decoder rejected**, **candidate accepted** and **trail not rendered**
  into distinct test outcomes. Include self-crossings, repeated letters,
  backtracking, long (>8 letter) paths and tap-vs-swipe gating.
- [ ] T-021.2 Replace the tiny starter Swipe vocabulary with
  sufficiently broad, frequency-ranked, independently licensed EN/DE
  lexicons. Record upstream versions, data licenses, attributions,
  memory and search time; verify the three affected English words are
  indexed and offer candidates. Avoid app-bundle bloat and loading
  large corpora into the main touch callback.
- [ ] T-021.3 Benchmark isolated decoders using the **same** synthetic
  ideal/noisy/self-crossing traces: existing geometric matcher versus
  JBoard's coarse+banded-DTW and Ortholinear's in-order key-pass/
  elastic matcher. Consider selective MIT-code adoption only if
  attribution/license obligations are met. Retain Swift/UIKit integration,
  QWERTY + QWERTZ geometry, no new touch-ownership layer. Verify top-1,
  top-3, false commits, p95 runtime and bounded memory. Do not assume
  clean-path synthetic success equals real-finger accuracy.
- [ ] T-021.4 Add a **manual opt-in** `Settings > Keyboard > Swipe
  Diagnostics` debug view: per-gesture touch began/moved/ended/cancelled
  count, path-point count (capped), glide gate result, dictionary hit
  count, decoder rejection reason, Canvas update/render state and
  bounded elapsed decode time. Show counters/flags only. **Never persist,
  upload or log raw swipe traces, intended/host text or passwords.**
  Clear indicators on new gesture, focus change and keyboard restart.
- [ ] T-021.5 Isolate ChatGPT-host trail invisibility from recognition.
  Audit `AlphabeticTouchRow` callback lifetime, `onSwipePath` resets,
  `SwipeTrailOverlay` Canvas redraw, child `.zIndex`, row overlays,
  cancellation, keyboard focus/dismissal and host-specific clipping.
  If SwiftUI Canvas remains unstable, test an existing-owner UIKit
  `CAShapeLayer` rendering path **without** adding JBoard's separate
  competing UIGestureRecognizer. Use same translucent brush styling.
- [ ] T-021.6 Optional **on-device** personalization: learn explicit
  accepted alternate choices and manually added words per preferred
  language; bound counts/weights and offer Forget/Reset. Consider
  bounded per-key calibration from explicit corrections only.
  Do not train on unconfirmed automatic guesses, record raw strokes,
  inspect unrelated host text, or use online prediction. Keep English
  and German preference ordering independent of Cantonese IME.
- [ ] T-021.7 Verify at least 30 consecutive gestures (including
  `penetrate`, `strange`, `tight`, loops and intersections) in
  ChatGPT, Notes and Altboard's own test field, including keyboard
  switching, focus change, dark/light, VoiceOver, finger cancellation
  and return to ordinary typing. Trail visibility and correct insertion
  must pass **separately**. Check no duplicate UIKit touch layer,
  no haptic/Space-trackpad/accent/ASR regressions.
- [ ] T-021.8 When implementation is explicitly requested, run
  targeted pure Swift corpus/decoder tests first and only then use
  the **existing** `.github/workflows/build-unsigned-ipa.yml` from
  `main` for one physical-iPhone SideStore build. Preserve #70 as the
  last confirmed green build until new acceptance. **No IPA for this
  documentation-only research/task commit.**

Full baseline and follow-on research:
`docs/swipe-typing-en-de-plan.json` (`investigation20261103`).
T-021 expands the already-open T-005.6/5.7 work; do not
implement a second independent Swipe system or duplicate dictionaries.

## P1 — Common long phrases and segmentation (T-013)

- [x] T-013.1 Audit supplemental Cantonese list: 162 entries, just 2 with five or more characters; this excludes the main upstream dictionary.
- [x] T-013.2 Specify one Traditional Chinese phrase + validated tone-numbered Jyutping reading, deriving Yale and Sidney Lau automatically.
- [ ] T-013.3 Collect and validate frequency-ranked 3–10 character Hong Kong spoken phrases against upstream and linguistic sources; deduplicate and check tone readings.
- [ ] T-013.4 Append reviewed entries (not merely proposed examples) and test all three complete spelling forms.
- [ ] T-013.5 Implement bounded syllable-segmentation / beam search for per-syllable mixed spelling within a long phrase, without 3^n stored combinations.
- [ ] T-013.6 Measure full-corpus recall, false matches, p95 iPhone latency, memory and English-input interference.
- [x] T-013.7 Diagnose Action #61: Sidney Lau mapping erroneously converted 'jeung' to 'jung'; correct Yale jy- onset and suffix-only mappings, add regression tests. CI still pending.

See `docs/CANTONESE-LONG-PHRASES-PLAN.md`.

## P0 — Swipe trail + native Emoji parity (T-016, BEFORE QA fork merge)

User-reported iPhone feedback from successful IPA #63 (`8c1d6b2`). Work isolated on
`feat/swipe-trail-emoji-native-parity-20261102`. Do not merge the separate T-014/T-015 QA branch.

- [x] T-016.1 Diagnose "to" rejected: 3-point decoder gate, 3-key glide gate, tiny dictionary missing `to`. Add bounded two-letter path support and baseline EN/DE short words.
- [x] T-016.2 Draw an ephemeral visible swipe trail from existing UIKit `AlphabeticTouchRow` touch callbacks into a noninteractive Canvas across letter rows. Do not add a gesture recognizer.
- [x] T-016.3 Record measured pixel/point screenshot reconstruction in `docs/ios-emoji-native-parity-IMG_9692.json` (full 10kB user-download version also provided).
- [x] T-016.4 Replace Emoji vertical scroll + top text chips with 8x4 horizontal pages + bottom category-icon rail, full-width search, ABC and repeat Delete. Remove Genmoji, duplicate emoji key and space/return keys from Emoji mode.
- [x] T-016.5 Add local frequent emoji ordering (usage count then recency), 96-entry cap; never collect host text or raw gesture data.
- [x] T-016.6 Retain Unicode Emoji 18 source with version metadata and conservatively filter likely unsupported glyphs on the installed iOS version to avoid missing-glyph squares.
- [ ] T-016.7 CI branch build success and IPA artifact inspection; binary must include the versioned catalog and keyboard extension.
- [ ] T-016.8 Real iPhone screenshot overlay comparison, 2-letter glide traces, hitbox and gesture cancellation, no false glide on quick correction, frequent use persistence, Emoji search/ABC and Delete verification.
- [ ] T-016.9 Reassess corpus vs MIT-licensed `nkrsn/jboard` and `isaced/ISEmojiView` only after iPhone test; do not copy GPL iSwipe or unlicensed sswipe source.
- [ ] T-016.10 Merge T-016 only with reviewed passing IPA and user device feedback. T-014/T-015 QA work remains separate until then.

## P0 — Visible Numbers and Symbols glyphs (T-018)

Physical iPhone screenshots IMG_9698.jpg and IMG_9699.jpg show widespread
empty keycaps on number/symbol rows. This regression already existed in #64.
Cause: `KeyButton.symbolText` delegated punctuation to `GlyphPath` and
returned a blank path for unhandled font fallback, especially Traditional
Chinese symbols. Restore all direct and callout labels with
`Text(verbatim:)` while preserving key targets and inserting original glyphs.

- [x] Change KeyButton symbol and callout rendering to platform font fallback.
- [x] Add source regression tests for 10/10/5 key rows across Alphabet/Symbols.
- [x] Integrate offline unit tests and exact-SHA IPA bundle inspection into the
  existing single unsigned-IPA build workflow, before artifact publishing.
- [ ] Verify final IPA actually compiles and passes full package checks.
- [ ] Test every symbol layer on physical iPhone, including Chinese brackets.
- [ ] Test iPhone globe switching, swipe loops, Cantonese adaptive preference.
- [ ] Do not mark device verified until the screenshots match visible labels.

## P0 — Combined iPhone Preview (T-017)

- [x] #64 base kept intact; targeted QA fixes and tests combined.
- [x] Replace custom Emoji UI with system Globe input-mode selector.
- [x] Theme-aware tapered swipe brush; add "become"/"evermore".
- [x] Bounded explicit-choice Cantonese scheme-preference learning.
- [x] Add README iPhone testing checklist for each workflow.
- [ ] Confirm combined IPA passes Xcode and artifact integrity checks.
- [ ] iPhone swipe looping/repeated-letter path quality and Globe menu acceptance.

## P0 — Universal Cantonese Input (T-012)

- [x] T-012.1 Build indexed Jyutping, Yale and Sidney Lau spellings in the same SQLite dictionary; users never select a scheme.
- [x] T-012.2 Remove the Cantonese Romanization picker; keep legacy saved values ignored.
- [x] T-012.3 Provide narrow `mm → m` and `ng → m` input aliases. Genuine `ng` candidates remain, with 唔 offered as a separate candidate. Preserve tone-digit strictness.
- [x] T-012.4 Include Sidney Lau phonetic boundaries in held-Delete and regression tests for user-entered examples.
- [x] T-012.5 Fix run 41528118833 Xcode duplicate resource output by excluding `.gitkeep` from keyboard extension resources.
- [ ] T-012.6 Complete macOS Xcode build, SideStore IPA delivery, and on-device verification after changes.
- [ ] T-012.7 Per-syllable mixed romanization inside compound phrases, rather than one whole phrase per convention.
- [ ] T-012.8 Tune candidate ranking, frequency and offline p95 latency/memory for complete corpus.
- [ ] T-012.9 Context-sensitive lazy-sound aliases and stronger typo recognition without conflating true phonological distinctions.

See `docs/CANTONESE-UNIVERSAL-IME-ACCEPTANCE.md`.

## P0 — Cantonese input enrichment and emoji (T-010 / T-011)

- [x] T-010.1 Add audited colloquial entries and multiple-character conversational phrases, including 喎, 尐, 噤, 或者, 根據, 最多.
- [x] T-010.2 Replace broad string substitutions with three indexed romanization systems plus narrow informal aliases. Full mixed-phrase fuzzy input remains T-012.7.
- [x] T-010.3 Present opt-in next-word continuations after candidate commits; never silently insert predictions.
- [x] T-010.4 Switch alphabetic numeric and symbol punctuation to Chinese forms when yue/zh is in the selected preferred languages; provide manual paired quotes and extended title/bracket keys.
- [x] T-011.1 Generate full, offline Unicode fully-qualified emoji catalog with category chips, search and ABC return.
- [ ] T-010.5 Fix high-accuracy multiword *Latin* typo corrections, including merged/unseparated text and transpositions; current OS checker remains word-scoped.
- [ ] T-010.6 Optional first-run Cantonese orthography variant choice / Skip and per-user preference; do not force replacements.
- [ ] T-010.7 Independent romanization mapping validation against authoritative syllable lists; confirm chosen source-version discrepancies rather than claim perfect Yale.
- [ ] T-010.8 Upgrade ranking: currently phrase supplements and corpus-order next-word completions, not a trained language model or proven full phrase/typo coverage.
- [ ] T-011.2 Verify Unicode data release availability, CLDR names, all skin tone/ZWJ handling, iOS glyph support, native-like search behavior and accessibility on device.
- [ ] T-010.9 Full Xcode/SideStore build and physical keyboard testing after commit 0dc80fdec1d2.

## P0 — Immediate interaction and manual AI text rewrite (T-008)

- [x] T-008.1 Manual AI uses UIInputViewController.selectedText instead of cursor prefix; auto AI action remains dictated transcript only.
- [x] T-008.2 Selection changed during inference: copy result without overwriting a different host field.
- [x] T-008.3 Explicit Use Clipboard fallback (requires Full Access and iOS permission), process selected copied text, return output to clipboard for manual paste; never silently replace.
- [x] T-008.4 AI action picker REPLACES gear/output/mic toolbar, not a floating overlay; no global UIScrollView.appearance() mutation.
- [x] T-008.5 Optional Show Settings Key, default on; when hidden, long hold Output Language (0.7s) to open Settings.
- [x] T-008.6 Double-tap newly activated microphone quickly (within 1.3s) or retap during Starting to cancel without ASR finalization. Preserve ordinary Stop after the cancel window.
- [x] T-008.7 Single Backspace tap deletes one host character; fast Cantonese syllable deletion after 310ms hold; regular hold 420ms.
- [x] T-008.8 Space trackpad movement suppresses IME/Latin suggestions; refresh 500ms after release.
- [x] T-008.9 Delay synchronous Cantonese SQLite suggestions by 24ms beyond key-down UI path and cache swipe key centers.
- [x] T-008.10 Warn once when recording exceeds 40s, then compact triangle + elapsed seconds at mic's left.
- [x] T-008.11 Emoji picker retains ABC, Emoji, Space, Return and repeat Delete.
- [ ] T-008.12 Xcode compile / SideStore IPA, host-selection rewrite and clipboard entitlement tests.
- [ ] T-008.13 Device test immediate haptic/pressed states, no accidental recording after cancelled start, mic start/stop race, privacy and no dropped input.
- [ ] T-008.14 Test quick text cursor drag with both Cantonese and Latin suggestions, including focus loss/cancel.

## P1 — Cantonese conversational ASR vocabulary review (T-009)

- [x] T-009.1 Create review-only vocabulary and normalization notes.
- [ ] T-009.2 User confirms preferred traditional spellings and which alternatives to preserve.
- [ ] T-009.3 Add confirmed mappings to non-destructive ASR postprocessing (never conflate particles or English letters).
- [ ] T-009.4 Test code-switching and short filler noises against real recordings before enabling.

See docs/CANTONESE-COLLOQUIAL-ASR-REVIEW.md.

## P0 — Native keyboard parity (T-001)

- [x] T-001.1 Measure native versus Altboard key positions, width, spacing and RGB color.
- [x] T-001.2 Adjust Alphabet first-row inset to 3.67pt and second-row to 25pt; preserve Shift/Backspace geometry.
- [x] T-001.3 Reduce full typing canvas from 290pt to 277pt and retain Mic-only Default/Compact.
- [x] T-001.4 Remove the extra center Space icon, retain small bottom-right A only on letters.
- [x] T-001.5 Numeric/symbol third row: remove duplicate ABC, keep #+=/123 toggle and bottom-row ABC.
- [x] T-001.6 Space after punctuation returns to letters; numbers stay on numbers.
- [x] T-001.7 Make the pressed key fill visibly different on touch, including brief quick-tap highlight.
- [x] T-001.7b Extend the same 80ms quick-release highlight to ordinary KeyButton controls, digits and punctuation.
- [x] T-001.7a Synchronize the onboarding preview's blank Space, small A, filled Emoji and row insets; remove its unused Space glyph position.
- [ ] T-001.8 Confirm no clipping or unexpected keyboard height with iPhone 17 Pro Max; both QWERTZ and QWERTY.
- [x] T-001.9a Match RGB(33,33,33) dark keyboard face with the host's native lower strip observed in IMG_9687 and IMG_9688; physical test still needed.
- [x] T-001.9b Native Emoji icon: screenshot-traced 56px transparent-cutout SVG shape rendered at 18.67pt in both keyboard and preview.
- [x] T-001.9c Numeric/symbols 10-key rows now have 6.67pt edge insets; 7-key third row uses 50pt wide keys, 14.67pt group gaps and 54.67pt punctuation keys at 440pt keyboard width.
- [x] T-001.9d Increase Delete glyph from 18pt to 19.25pt after comparing native 61×51px and old Altboard 57×48px glyphs.
- [x] T-001.9e Display native-looking curly double/single quote labels on Symbols, while continuing to insert existing ASCII characters.
- [x] T-001.9f Add deterministic 440pt/3x numerical geometry assertions for all numeric/symbol row positions.
- [x] T-001.9g Document every one of the 31 native numeric/symbol key rectangles, horizontal gaps, native/Delete Emoji glyph sizes and bottom-row widths in docs/ios-keyboard-symbols-reference.json.
- [x] T-001.9h Correct Alphabet third-row letter inset: 14.67pt Shift-to-Y gap requires 11.67pt HStack spacing plus internal 3pt letter padding. Native Y begins x=214px and M begins x=994px at 3x.
- [x] T-001.9i Record all 32 Alphabet keys' measured native versus previous Altboard rectangles in docs/ios-keyboard-alphabet-reference.json; avoid shrinking pixel-matching bottom row.
- [ ] T-001.9 Verify dark/light palette and host rounded corners, Emoji shape, all symbol row spacing and Delete symbol on-device in ChatGPT, History and Notes.

Files: `Shared/KeyboardLayoutGeometry.swift`, `Shared/KeyboardPalette.swift`,
`SayboardKeyboard/Views/AlphabeticTouchRow.swift`, `SayboardKeyboard/Views/SpaceBarKey.swift`,
`SayboardKeyboard/Views/Layouts/{AlphabeticKeyboardLayout,KeyboardChrome}.swift`,
`docs/ios-keyboard-reference.json`.

## P0 — Cantonese candidates and Yale tolerance (T-002)

- [x] T-002.1 Exact single-character candidates ahead of prefix-only phrase matches.
- [x] T-002.2 Deduplicate identical visible Chinese glyphs; preserve local selection-count ranking.
- [x] T-002.3 Right-hand chevron expands a bounded 4-column, vertically scrolling grid.
- [x] T-002.4 Untoned `ng` additionally offers `唔` as a convenience alias; retain canonical `m4` reading.
- [ ] T-002.5 Physical tests: `m`, `ng`, `gamjat`, `gamyat`, `唔OK`, grid scrolling, candidate insertion once.
- [ ] T-002.6 Verify tone-number strictness, deleted syllables and cursor movement in host field.
- [ ] T-002.7 Validate full dictionary candidate counts under memory/latency budget.

Files: `SayboardKeyboard/JyutpingDictionary.swift`,
`SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift`.

## P1 — Touch targets and feedback (T-003)

- [x] T-003.6 Restore Settings > Keyboard navigation icon (SF Symbol: keyboard).
- [x] T-003.7 Set unified default Core Haptics strength to 55%, retain existing stored values, add Reset button and regression test.
- [ ] T-003.8 Verify Reset to Default and test pulse at 55% on physical iPhone. Apple's built-in keyboard strength cannot be read.


- [x] T-003.1 Preserve contiguous key touch cells and 12%/18% bounded predictor.
- [x] T-003.2 Retain overlay showing visible keys and hit cells, without recording typed text.
- [x] T-003.3 Key-down/quick-release pressed highlight prototype.
- [x] T-003.3a Replaced delayed SwiftUI alphabet DragGesture with direct UIKit touchesBegan/moved/ended/cancelled in isolated review branch; quick-tap flash and accents retained.
- [ ] T-003.3b Verify pressed highlight is visible on the **initial touch-down**, including a very short stationary tap, on the physical iPhone.
- [ ] T-003.4 Real-device haptic latency, long-press accent popup, swipe-to-correct, trackpad cursor, boundary/dead-zone tests.
- [ ] T-003.5 Inspect both regular symbols and isolated Symbols keyboard kind.

## P1 — Safe code hygiene and toolchain (T-004)

- [x] T-004.1 Isolated cleanup: unused `SpaceBarKey.accumulatedOffset` removed.
- [x] T-004.2 Removed duplicate SwiftLint no-op Xcode post-compile hooks, retained string lint.
- [x] T-004.3 Created `docs/REPO-HYGIENE-SWIPE-AUDIT-2026-11-02.md`.
- [ ] T-004.4 Align SwiftFormat 6.2 settings versus XcodeGen Swift 6.1, with pinned tooling.
- [ ] T-004.5 Scan reference usage before deleting legacy persistence, unused animation parser or compatibility helpers.
- [ ] T-004.6 Fix potential duplicate/contradictory comments and docs only after verifying behavior.
- [ ] T-004.7 CI Swift compiler + focused tests and on-device regressions.

## P2 — Latin-script swipe typing (T-005)

- [x] T-005.1 Audit Henryikenna/sswipe and update offline English/German plan v2.
- [x] T-005.2 UIKit per-row touch owner retains finger capture beyond its bounds; global Q/A/Z coordinates and gesture-state gate without installing competing gesture layers.
- [x] T-005.3 Initial offline English/German lexicons reuse existing built-in common words only; no unlicensed sswipe or dictionary code copied.
- [x] T-005.4 Prototype resamples 32 points, endpoint prefilter, location + length + corpus-order ranking; smoke tests added.
- [x] T-005.5 Swipe Typing (Beta) keyboard setting, default off; inserts top result plus space, top-3 alternate candidates can replace verified suffix.
- [ ] T-005.6 Run pure Swift smoke and native build; physical-device accuracy, long-press accents, and keyboard hitbox regression tests.
- [ ] T-005.7 Expand from small starter corpus to adequately licensed frequency-ranked EN/DE dictionaries; measure p95 and top-3 accuracy.
- [ ] T-005.8 Enable by default only after iPhone acceptance. Native parity not claimed.

Plan: `docs/swipe-typing-en-de-plan.json`.

## P3 — Experimental live meeting transcription (T-007, PLAN ONLY)

- [x] T-007.1 Outline incremental offline transcription and meeting-assistant prototype architecture.
- [ ] T-007.2 Select ASR engine and measure real streaming/chunked decoder support (Qwen3 ONNX streaming not assumed).
- [ ] T-007.3 Prototype VAD, overlapping 2–4s segments, provisional vs final text, timestamps, diarization feasibility and corrections.
- [ ] T-007.4 Document consent, on-device file handling, recording visibility, retention, battery and thermal constraints.
- [ ] T-007.5 Add test-only flag after Swipe Typing is stable. Not coded or released now.

See docs/live-meeting-transcription-experiment.json.

## Build / deployment (T-006)

- [x] T-006.1 Current baseline Action #51 succeeded: `db687a7`.
- [ ] T-006.2 Compile the latest branch and run all policy tests; most recent prior successful beta was run 41522770022 at `e0c1901`.
- [x] T-006.2c Diagnose run 41528118833: duplicate `.gitkeep` extension resource. The project exclusion fix is committed for CI verification.
- [x] T-006.2a Switch IPA preview from macos-15 ARM64 to macos-15-intel hosted runner after zero-step cancellations (#52/#54); Xcode 26.2 installation confirmed in GitHub runner-images.
- [x] T-006.2b The macOS Intel runner previously compiled and shipped a SideStore IPA at Action #57; new branch still requires its own build.
- [ ] T-006.3 Verify SideStore IPA includes all extension resources and matching commit SHA.
- [ ] T-006.4 Physical iPhone confirmation before merging and publishing.

## Ticketing migration

When the repository's GitHub Settings > General > Features > Issues checkbox is
enabled, create one Issue per T-001…T-013, linking this file and retaining
subtask checkboxes. Until then, this Markdown file plus the draft PR review
serve as the issue board; do not claim that GitHub Issues were created.

