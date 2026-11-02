# Altboard-Canto development tasks

Source branch: `feat/instant-input-ai-swipe-20261102`
Last successful beta IPA: run 41522770022 (`e0c1901`). Run 41528118833 failed on duplicate `.gitkeep` resource outputs. The universal-input changes are not yet built or iPhone-verified.
The existing successful release branch and IPA remain unchanged. This branch publishes to its own beta Release tag.
GitHub Issues are disabled in this repository (GitHub API 410). This file is the
canonical, versioned ticket board until Issues are enabled.

Statuses: [x] implemented in review branch; [ ] pending or not verified.
Code changes are not considered shipped until a successful iPhone build and
physical checks, and a deliberate merge/release.

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
