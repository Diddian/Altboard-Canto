# Altboard-Canto — low-risk QA and hygiene half-wave

**Source:** `review/qa-half-wave1-20261102` branched from `docs/roadmap-after-swipe-before-live-20261102` at `65bf43b`, which contains the feature snapshot `9e055f7` plus the deferred task-order change. The live IPA branch `feat/instant-input-ai-swipe-20261102` is **not modified** by this work. The workflow only watches a finite list of branch names, and this isolated review branch is not in that list.

## Acceptance and current state

| Scope | Progress label | Evidence in review branch | Still required before shipping |
| --- | --- | --- | --- |
| 1. Build stability | 50% planning/testing coverage | Reviewed #60 duplicate resource, #61 Sidney alias regression and #62 active run; did not modify workflow. | Final result of #62, resource inclusion, Xcode archive + unsigned IPA and SideStore test. |
| 2. Cantonese spelling correctness | 50% review coverage | Existing Python canonical-index cases and Swift smoke tests verified by source review; existing test suite preserved. | Full dictionary coverage, on-device p95, tone/mixed-scheme testing. |
| 3. Emoji | 50% review coverage | Fixed brittle emoji-test comment parsing, added flag/ZWJ/skin-tone fixture checks, preserved resource format. | Real Unicode download/build, full character count, emoji support on target iOS, search UI height. |
| 4. Chinese punctuation | 50% review coverage | Existing full-width rows, CJK brackets, smart quote toggle reviewed; no invasive key geometry change. | Functional iPhone tests: 《》,〈〉,【】,〔〕,「」,『』, punctuation/space transitions and quote reset across cursor moves. |
| 5. Settings | 50% review coverage | Removed stale romanization-picker documentation, clarified legacy enum, kept persisted data untouched. | iPhone Settings persistence, long-press Settings path, preview parity and haptic reset. |
| 6. English / German | 50% review coverage | Expanded small built-in offline lexicons and one-edit user-selected spell suggestions, case matching through existing pipeline. | Local scripted smoke/Swift typechecking, device suggestion quality, frequency ranking, split/merged word handling. |
| 7. Hygiene | 50% audit scope | Identified complementary `AlphabeticLetterKey` (visual/accessibility) vs `AlphabeticTouchRow` UIKit physical surface; do not delete either. | Full symbol/ref scan, repeated touch/tap fixture and iPhone event trace. |

These percentages are **checklist milestones**, not quantitative code coverage, not source of truth for functionality, and not a claim that any tests were executed successfully. No changes to CI workflow YAML, Xcode signing, app bundle IDs, IPA release tags or core dictation/AI lifecycle.

## Key forensic findings

1. **Touch event ownership**: `AlphabeticTouchRow.swift` has one transparent UIKit `ImmediateKeyTouchView` overlay per row for physical touches, separate from SwiftUI accessibility actions. Calling this a duplicate tap handler and deleting one blindly would regress either VoiceOver or touch-down latency. The row's `beginTouch/moveTouch/finishTouch` tracks a swipe session; keep its state machine intact for this half-wave. Check for duplicate insertion via instrumented tests, not by guess.
2. **Keyboard actions**: `KeyboardLLMActionsToolbar` wraps `LLMActionBar` and is called from Alphabet/Extended modes as a replacement toolbar. This is intentional layering, not duplicate controls. Review of the three root view branches is required before removing or combining them.
3. **Stale persisted romanization**: `CantoneseRomanizationScheme` remains referenced by `SharedSettings` and existing persistence tests; it no longer drives candidate lookup. Deleting it outright is a data migration, not safe cleanup.
4. **Emoji**: the source is Unicode emoji-test.txt. Parsing text comments should use `glyph E<version> English name`; the previous split/regex was fragile. The updated fixture covers a flag, ZWJ profession and skin-tone sequence while excluding non-fully-qualified rows. Complete Unicode-version/glyph verification remains.
5. **Latin suggestions**: `UITextChecker` remains the primary offline source where installed. The added *bounded*, case-preserving fallback uses common vocabulary. One edit means insertion/deletion/substitution or adjacent transposition; it cannot and does not claim `typerecognitjon` → `type recognition`. No background collection or auto-replacement.
6. **Chinese punctuation**: the existing Symbols view inserts direct Unicode punctuation via `KeyboardProxy.insertText`. The quote state toggles only when the key is used, which may become stale after external host cursor changes. Do not add second touch handlers or perform silent host text edits.
7. **Build**: failing #60 resource collision and #61 Python test were on the IPA branch before the source snapshot. The current isolated review branch must not trigger build jobs automatically. The last known successful beta before #62 was #58 (`e0c1901`).

## Next 50%: mandatory gates, in order

1. Confirm current feature branch head and #62 result. If failed, inspect **only the failing job and first error**, fix on an isolated build-fix branch, not by changing this QA branch blindly.
2. Run `python3 -m unittest discover -s scripts -p 'test_jyutping_*.py'`, `python3 -m unittest discover -s scripts -p 'test_universal_cantonese.py'`, and `python3 -m unittest discover -s scripts -p 'test_emoji_catalog.py'`. Verify Unicode version and data-size guard. Never claim green without logs.
3. Run Swift pure policy smoke for `LatinWordSuggestionPolicy`, `CantoneseRomanizationVariants`, `CantoneseSyllableEditing` and keyboard geometry. Compile extension with Xcode *on a non-release QA branch* only after the currently running build finishes.
4. Verify Latin error-correction behavior, especially German umlauts and exact English passthrough. Measure and cap false-positive suggestions; user selection stays mandatory.
5. Add pure punctuation and quote-state tests, then check real host cursor changes before enabling further smart-quotes.
6. Audit duplicate touch events using actual `AlphabeticTouchRow` callback paths and debug traces; check VoiceOver and held accents. Remove only symbols proven unused by all current app+extension targets and compatible settings keys.
7. Run actual iPhone: no double insertions, no dropped letters, key highlight, Emoji ABC, keyboard height, haptics reset, AI manual selection and mic cancel.
8. Only after tests pass: incorporate review changes into feature branch by a small reviewed PR; do not force-push, merge or overwrite the current rolling IPA merely to reach a nominal percentage.

## Deferred ordering

Stable IPA and six low-risk tracks → Swipe Typing Beta → common long Cantonese phrases and per-syllable mixed spelling → Live Transcription (planning only).

## New-chat continuation prompt

Use the repo `Diddian/Altboard-Canto`. My QA branch is `review/qa-half-wave1-20261102`, based on `docs/roadmap-after-swipe-before-live-20261102`. The live IPA branch is `feat/instant-input-ai-swipe-20261102`. Read `docs/SAFE-HALF-WAVE-2026-11-02.md` and `docs/TASKS.md`. Continue **only the remaining half** of T-014 items 1–6 plus evidence-led hygiene; do not exceed task-level completion goals without explicit reason. First check the #62 build result, keep the unsigned IPA workflow and its branch/release untouched, and determine whether the QA branch remains based on the right live commit. Run the Python/Swift tests, fix actual failures, check Emoji Unicode data and Chinese punctuation, test Settings persistence and bounded Latin typo suggestions. Audit duplicate triggers by finding the owning touch path; do not erase accessibility handlers, persisted settings, old branches or working ASR/AI code merely because they look redundant. If a build is needed, do it only after #62 finishes, isolated from the rolling beta. Update precise evidence and pending checks in the task board; report counts, tests and a conservative task-level percentage. Leave long-phrase mixed spelling **after Swipe Typing and before Live Transcription**. Do not merge without evidence of passing Xcode and host-app keyboard tests.
