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

## Added keyboard dismissal

- A top-edge-only UIKit pan recognizer calls UIInputViewController.dismissKeyboard().
- Pure policy checks vertical movement and quick flicks; horizontal drags stay active.
- History focus clears on outside taps and interactive scroll; record actions remain active.
- KeyboardInputTrace records a text-free keyboardDismissRequested event.
- Third-party apps own their own outside-tap behavior and cannot be patched by a keyboard extension.
