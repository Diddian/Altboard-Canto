# Jyutping typing mode integration for Altboard-Canto

Status: architecture reviewed, IME integration not yet implemented. The current English Keyboard types Latin characters; it must not be described as a functional Jyutping IME.

## Source reviewed

- https://github.com/yuetyam/jyutping (CC0-1.0 repository)
- Modules/CoreIME/Sources/CoreIME/Engine.swift, Lexicon.swift, VirtualInputKey.swift
- Modules/Preparing (generated offline lexicon)
- Keyboard/SharedViews/CandidateBar.swift and CandidateBoard.swift
- Keyboard/SharedModels/InputMemory.swift and InputMethodMode.swift
- Keyboard/iPhone/GlassKeys/GlassLetterInputKey.swift and LegacyKeys/LetterInputKey.swift
- Keyboard/SharedModels/HapticFeedback.swift and Keyboard/KeyboardViewController.swift
- Verify separately the licenses attached to Rime-Cantonese and OpenCC data before bundling any dictionary artifacts.

## Contract

Reuse Altboard's existing key positions, adjustable height, QWERTZ/QWERTY order, shift/delete/space/emoji, mic session, theme and direct haptic feedback. Do not import the reference app's entire keyboard view or controller. English typing stays usable without voice model installation.

A Jyutping typing mode is an IME, not a transliteration label:

1. Letter taps append to a noncommitted composition buffer rather than immediately insert Latin text.
2. CoreIME + the bundled offline lexicon produce Traditional Hong Kong Chinese candidates, supporting tones, common habitual spellings, and abbreviated initials.
3. A candidate strip in the keyboard's upper area displays and selects Chinese characters and Jyutping hints. Space selects the first candidate. A chosen candidate commits its Han characters; Return depends on whether a composition is active.
4. Backspace edits the composition before touching the host's text. Host app changes and cursor motion must not silently commit incomplete input.
5. English/Jyutping mode toggle plus a saved startup mode. Microphone dictation keeps its normal path; it must not corrupt an uncommitted composition.
6. Persist optional personal candidate frequency locally with a reset/export facility.

## Build phases

1. Extract minimal CoreIME code and required dependencies into a pinned internal Swift package. Audit licenses and database resources.
2. Generate the SQLite lexicon offline using upstream Preparing; record its size, schema version and SHA. Either pin the generated artifact or regenerate deterministically in CI.
3. Implement adapter: append(key), backspace(), candidates(prefix), choose(id), clear(), commit(), plus space/return rules.
4. Build Altboard-native candidate UI and adapt to all keyboard heights (70–110%), including narrow widths and large text settings.
5. Regression test: nei5 hou2 → 你好, ngo5 → 我, sik6 → 食, multiword segmentation, tones/no tones, abbreviations, punctuation, cursor, app switching and microphone.
6. Benchmark memory and latency on iPhone. Do not run ASR/LLM per keystroke; index the local lexicon for bounded lookup.

## Current completed/staged scope

- English Keyboard and Symbols retain all keys while recording; mic-only retains fade and gray status. Non-mic modes use microphone waveform/loading animation alone, with no additional gray raw/final transcript labels.
- Native UIKit impact feedback per key with an adjustable shared strength and tappable Settings preview.
- Alphabetic keys styled with system regular typography, compact key corners and 380ms hold-to-select accented characters.
