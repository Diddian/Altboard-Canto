# Altboard-Canto — Code hygiene and swipe architecture audit

Source snapshot: `db687a77984790605c7b0fe5d5d2068fbb8cb5af` (2026-11-02).
Review branch: `chore/audit-hygiene-swipe-plan-20261102`.
The running `feat/fixed-keyboard-settings-20261102` build branch, workflow YAML, release and PR #4 are **unchanged**.

## Confirmed safe cleanup in this branch

1. `SayboardKeyboard/Views/SpaceBarKey.swift` — removed `accumulatedOffset`, which was only initialized and reset; actual cursor movement already uses `lastReportedCharOffset`.
2. `project.yml` — removed two duplicate, no-op SwiftLint post-compile steps (one per app/extension). They only printed whether SwiftLint was installed. Kept the working `scripts/lint-strings.sh` build step.
3. Deleted two unnecessary comments asserting native Apple behavior without measurements. No input-handling logic or timing was changed.
4. Expanded the **existing** `docs/swipe-typing-en-de-plan.json` rather than creating a second competing machine-readable plan.

## Verified toolchain findings — deferred, no workflow modification

- `.swiftformat` is present and configured with `--swift-version 6.2` and `--language-mode 5`; `project.yml` builds with `SWIFT_VERSION: "6.1"` plus strict concurrency. This is not proof of a compiler error; align tool version policies in a separately tested change. Do not mass-reformat the keyboard.
- `.swiftlint.yml` and `.swiftformat` both exist with partially divided rule ownership. They need one documented manual/CI entrypoint and a pinned version.
- `.github/workflows/build-unsigned-ipa.yml` installs SwiftLint but does **not** run `swiftlint lint`. Because current IPA build is running, leave its YAML untouched; later either run an explicit lint check in a non-release job or remove the unnecessary installation. Avoid a new failure on the release-critical path.
- `project.yml` still builds `scripts/lint-strings.sh`, which is an actual validation action and must not be removed.
- Do not delete `Shared/LlamaRuntime.swift`, old persisted keyboard settings or entitlement/StoreKit-related compatibility classes just because they are small or named "legacy". A full current-ref symbol and persistence audit is required first.

## Similar code, but NOT proven dead

- `Shared/MicMorphFrames.swift` and `SayboardKeyboard/Views/SpinnerMorphFrames.swift` each implement SVG-path parsing for different embedded animation sequences. Consider extracting a shared parser only with animation snapshot tests; do not merge their frame data.
- `SayboardKeyboard/Views/AlphabeticLetterKey.swift` is now **visual-only**; the active gesture belongs to `AlphabeticTouchRow.swift`. These are complementary, not duplicate key handlers.
- `Shared/KeyTouchMap.swift` is touch-boundary math and `AlphabeticTouchRow.swift` owns view/gesture state; both are needed.
- `LatinWordSuggestions.swift` uses synchronous system spelling calls after a 45ms delay on the main actor. Measure latency before treating the delay as proof of a non-blocking keystroke path.
- Existing `docs/CODE-AUDIT-2026-11-02.md` retains historical fixes; do not erase it. This document tracks only the new isolated hygiene review.

## sswipe findings relevant to Latin-script glide

Reference: [Henryikenna/sswipe](https://github.com/Henryikenna/sswipe). Inspected:
`lib/engine/swipe_decoder.dart`, `geometry.dart`, `dictionary.dart`,
`keyboard_widget.dart`, `key_layout.dart`, and its tests.

- This is a Flutter **Windows desktop** floating keyboard, not an iOS keyboard extension.
- Generalizable approach: single down/move/up path, tap/glide state gate, candidate prefilter by start/end letters, path-length resampling to 64 points, absolute location + normalized shape + length + frequency ranking, top candidate and correction choices.
- Do not reuse the desktop keyboard's 18×6 geometry, Win32 SendInput integration, or Flutter rendering.
- No `LICENSE` file appears in the inspected sswipe tree. **Do not copy code or its bundled English dictionary** until rights and source provenance are confirmed.
- The bundled sswipe decoder works from a Latin a–z dictionary. German ß, umlauts, compounds and future French/Spanish/Portuguese diacritics require dedicated normalization and licensed corpora.

## Critical integration dependency

Altboard currently has three separate `AlphabeticTouchRow` gestures. That design fills touch gaps **inside** rows, but does not own a complete glide when a finger crosses Q→A→Z. Simply adding a fourth global SwiftUI `DragGesture` would compete with tap, accent, and slide-correction gestures.

Implement the next feature **behind a disabled-by-default flag**, in a new feature branch:

1. Define immutable key-plane geometry for all three rows from real visual key centers, including QWERTZ versus QWERTY.
2. Replace separate row gesture owners (not their visual keys) with one keyboard-level capture/coordinator. Keep Space, Shift, Return, Emoji, Backspace and Mic outside the glide region.
3. Detect tap / accent hold / glide before inserting text. On glide capture bounded points, release the gesture and decode off the input hot path.
4. Start with offline EN/DE word-frequency packs and path matching. Expand to other Latin-script preferred languages only with licensed dictionaries and per-language tests; no language toggle.
5. Verify insertion against host cursor state, preserve Cantonese input, measure physical iPhone accuracy and p95 latency. Do not enable by default until tested.

Detailed data flow, algorithm candidates, reference links, test gates and release constraints live in the updated [swipe plan](swipe-typing-en-de-plan.json).

## Verification performed and omitted

- Exact-match static checks for the deleted unused state and both no-op scripts.
- Parsed the updated JSON and confirmed the existing workflow file is not in the changed-file set.
- **Not run:** Xcode build, SwiftLint, SwiftFormat or iPhone typing tests. Do not merge this branch without the current IPA baseline and a separate build/review.

