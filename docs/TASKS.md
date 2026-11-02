# Altboard-Canto development tasks

Source branch: `fix/instant-touchdown-highlight-20261102`
Last verified IPA build: `ac34148` (Action #55). The new Emoji/geometry fixes are not yet compiled or tested.
The historical stable release branch is unchanged. The review branch has its own Preview IPA workflow.
GitHub Issues are disabled in this repository (GitHub API 410). This file is the
canonical, versioned ticket board until Issues are enabled.

Statuses: [x] implemented in review branch; [ ] pending or not verified.
Code changes are not considered shipped until a successful iPhone build and
physical checks, and a deliberate merge/release.

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
- [ ] T-006.2 Compile the new Emoji/geometry review commit and verify pure-policy tests. The earlier #55 build succeeded at `ac34148`.
- [x] T-006.2a Switch IPA preview from macos-15 ARM64 to macos-15-intel hosted runner after zero-step cancellations (#52/#54); Xcode 26.2 installation confirmed in GitHub runner-images.
- [ ] T-006.2b Confirm that the alternate macOS runner actually executes steps and ships an IPA.
- [ ] T-006.3 Verify SideStore IPA includes all extension resources and matching commit SHA.
- [ ] T-006.4 Physical iPhone confirmation before merging and publishing.

## Ticketing migration

When the repository's GitHub Settings > General > Features > Issues checkbox is
enabled, create one Issue per T-001…T-006, linking this file and retaining
subtask checkboxes. Until then, this Markdown file plus the draft PR review
serve as the issue board; do not claim that GitHub Issues were created.
