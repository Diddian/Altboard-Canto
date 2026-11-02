# Altboard-Canto: Settings and Redundancy Audit

Reviewed baseline: c6673851b63b (2026-11-02).
Implementation branch: feat/fixed-keyboard-settings-20261102.

## Findings repaired in this branch

1. The 70%-110% keyboard height setting changed the extension view height
   without giving all rows enough vertical space. Removed the slider and made
   all typing modes fixed-height. Added Default/Compact only for Microphone Only.
2. Alphabet toolbar used a negative vertical offset. It clipped the top
   buttons and mic. Use measured positive insets; remove alphabet pulse rings.
3. Runtime, settings preview and onboarding preview had different sizing
   constants. Shared/KeyboardLayoutGeometry.swift owns the fixed dimensions.
4. Space and microphone haptics triggered when the touch was released.
   They now trigger on touch-down; the Core Haptics engine is prepared earlier.
5. Each haptic wrote synchronously to App Group defaults on the input thread.
   Trace sampling is now queued on a utility queue.
6. Settings controls previously mixed speech, history, model cache, AI actions,
   keyboard layout and language settings on the first page. They are grouped
   into seven primary destinations plus About.
7. Preferred spoken languages had a dedicated picker embedded inside Voice
   Output, making it hard to find. It now sits on Speech & Languages.
8. Cleared outdated SharedSettings tests for the old height and typing-language
   switches. Added a fixed-layout policy smoke check in Actions.
9. Removed an empty onboarding source and the accidental Standard/Extended
   toggling that skipped the Alphabet keyboard.

## Preserved to prevent regressions

- History record and audio deletion confirmation.
- Compiled model cache deletion confirmation (downloaded models untouched).
- Cantonese romanization choice, live Latin input and offline suggestions.
- Single preferred spoken-language setting shared across voice and keyboard.
- Existing haptic engine selection for troubleshooting.
- Main Models tab (no duplicated model catalogue data).
- App Group sharing and SideStore signing/IPA packaging.
- Legacy per-app writing style compatibility data (not proven safe to delete).

## Remaining cleanup opportunities

- The runtime Alphabet keyboard and the Settings interactive preview still
  render different SwiftUI components, but both use shared dimensions. Fully
  sharing an interactive keyboard view requires injecting a mock text proxy
  and should be done only with UI tests.
- Setup and Diagnostics still implement similar microphone/ASR test flows.
  They can share one service without removing either entrypoint.
- App-specific writing styles are no longer reliable on modern iOS. Keep
  legacy data until migration and minimum OS support are verified.
- A hidden seven-tap Settings tab gesture still changes a custom spacebar.
  It is live, not dead; needs a separate user-facing decision.
- The fork's Report a Problem links still point to upstream Altboard. Do not
  silently redirect until a working fork support destination is established.

## Verification

- CI checks basic fixed geometry and the absence of the height slider.
- The physical iPhone build must compile both app and custom keyboard.
- A successful CI build does not prove the iPhone physically vibrates.
- Confirm Alphabet/Symbols height is fixed; Default/Compact only on Mic Only.
- Confirm toolbar buttons never clip when the keyboard appears in History,
  Notes, WhatsApp, and when changing the selected typing mode.
- Confirm voice processing/LLM and history controls still operate.
- Test each Settings navigation row and verify preferences survive relaunch.

## Removed unverified top-edge gesture

- The experimental keyboard-edge recognizer did not dismiss reliably on iOS 27.2.
- Remove it and its policy/smoke tests, avoiding gesture interference with typing.
- Keep host-owned History tap and interactive scroll dismissal.
- External host applications own their own background-tap behavior.

## 2026-11-02 native suggestion and typing adjustments

- Native screenshot IMG_9670: three equal suggestion columns, muted SF text,
  centered 1pt #323232 separators 24pt high, #1F1F1F background.
- During Cantonese composition, remove microphone and other toolbar controls
  completely so suggestions can use the entire width; extra candidates scroll.
- Latin typing remains live. Usage-based candidate ranking already persists in
  the App Group using canto.jyutping.selectionCounts.
- Spacebar trackpad activation reduced from 300ms to 150ms.
- Alphabet letter hit areas cover 3pt into each side of the visual 6pt gap.
- In-app History dictation uses existing Darwin bridge, not a deep-link bounce.
- Predictions and input measurements are screenshot approximations, not Apple
  published private geometry.

## Native UI comparison and English/German suggestions

- Old Altboard's first letter row began 51px below IMG_9658's native row
  (or 36px below the alternate IMG_9659 layout). The updated runtime places
  its first row at 57pt, 1px above IMG_9658's measured 172px start.
- Native and old visible letter-key rectangles had nearly identical width,
  height and gaps; no arbitrary key scaling was added.
- Review branch reduces the canvas from 290pt to 277pt after new screenshot
  comparison: bottom-row keys sat ~13pt above native. The baseline 290pt
  measurement was a container-height estimate, not the final key baseline.
- Native candidate glyph pixels measured near RGB(162,162,162), replacing
  the previous overly light #C7C7C7 target with #A2A2A2.
- The emoji icon now uses the filled face.smiling.inverse SF Symbol (~28pt).
- The Alphabet Space key gets a small A at bottom-right without changing
  its 150ms drag-to-cursor mode.
- English and German suggestions use the phone's offline UITextChecker and
  a deterministic fallback list; current host word is verified before editing.
- Latin selection frequencies are stored locally and separately from the
  Cantonese candidate counts.
- Swipe typing is intentionally NOT implemented yet: gesture capture must
  be refactored without breaking long-press accents or Space trackpad.
- Full 32-key screenshot data: docs/ios-keyboard-native-vs-altboard-pixel-comparison.json.
- Detailed glide typing plan: docs/swipe-typing-en-de-plan.json.

## Gap-free touch routing (new)

- Native visual key size preserved. A single row gesture owns all letter key taps.
- First and last touch cells also absorb margins; adjacent cells share boundaries.
- Touch rows divide the previously blank 11pt vertical gap.
- Predictive shifts are at most 12% of cell width, 18% combined with calibration.
- Prediction uses available offline suggestions, with neutral fallbacks.
- Swipe-to-correct and accent long-press are retained via one gesture handler.
- Diagnostic overlay: orange routed hit cells, dashed cyan visible keys.
- Previous 15-minute cancelled macos-26 runs had zero executed steps. Runner changed
  to macos-15, with explicit Xcode 26.2 availability check.
- Physical typing tests still required before calling this native-equivalent.
