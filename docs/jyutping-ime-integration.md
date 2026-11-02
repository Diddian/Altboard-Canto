# Altboard-Canto — Cantonese Alphabet IME

Reference implementation: [yuetyam/jyutping](https://github.com/yuetyam/jyutping), especially its CoreIME design, lexicon, candidate UI, and input memory. Altboard reuses the existing Alphabet keyboard and offline index; it does not embed the upstream keyboard UI.

## Keyboard behavior

1. In **Preferred Languages**, selecting **Cantonese** (`yue`) enables Chinese candidate suggestions. Selecting generic Chinese (`zh`) alone does not. There is no EN/粵 typing switch on the keyboard.
2. **Keyboard Type:** Microphone Only, Symbols, Alphabet. When Cantonese is enabled, one indexed lookup accepts **Jyutping**, **Yale**, and **Sidney Lau** together without a romanization selector. Legacy stored scheme values are ignored.
3. Every letter is inserted immediately into the application's actual text field, with iOS-like Shift and auto-capitalization. Chinese suggestions appear above the keyboard when recognized. Suggestions display **Chinese text only**, never tone digits or phonetic captions.
4. Selecting a Chinese candidate replaces only the just-typed Latin suffix after verifying that `UITextDocumentProxy.documentContextBeforeInput` still ends with that suffix. Changed cursor, empty, or truncated context means no replacement.
5. Space inserts a space, Return inserts a newline, and unknown spellings remain Latin. There is no need to switch to an English-only mode.
6. Backspace deletes a whole phonetic token only when it matches a **complete exact offline entry** and the visible suffix is verified. Prefix-only matches are not sufficient. Other typing uses ordinary character deletion.
7. Microphone, LLM, emoji and accessibility keep their existing behavior. The
   legacy 70–110% keyboard-height control has been removed; Alphabet and Symbols
   use fixed height. No LLM or network request occurs per key.

## Offline indexing

`scripts/build-jyutping-lexicon.py` pins `Modules/Preparing/Sources/Preparing/Resources/jyutping.txt` with a Git blob SHA. The builder indexes exact Jyutping without tones (`plain`), with tones (`compact`), unmarked Yale aliases (`yale`), unmarked Sidney Lau aliases (`sidney`), abbreviated initials, and stable priority. No runtime model download or server is necessary for typing.

Yale mappings include Jyutping `j → y`, `z → j`, `c → ch`, `oe/eo → eu` and the long `aa` search alias `a`. These aliases support ordinary phonetic typing; they do not claim to render scholarly Yale tone diacritics. Example: 今日 (`gam1 jat6`) matches both `gamjat` and `gamyat` with the same Chinese candidate.

## Verification and limitations

- CI runs `scripts/test_jyutping_yale.py`, the SQLite source-integrity and example checks (including 今日), `scripts/verify-keyboard-core.swift`, then an unsigned physical-iPhone SDK build.
- Unit tests cover shared preferences, romanization persistence, romanization composition and suffix safety. Real devices must verify long-press accents, automatic sentence case, keyboard switching, mixed-language editing, and smoothness.
- Ordinary English and Cantonese phonetic spellings can coincide. Exact dictionary matching reduces mistaken whole-word deletion, but a mixed-language keyboard cannot infer intent perfectly from letters alone.
- The offline candidate index does not port all of the source CoreIME's segmentation or sophisticated personalized ranking. A pinning strategy and applicable data-license obligations are recorded in `docs/JYUTPING-DATA-NOTICES.md`.

## Deliverable

The workflow `.github/workflows/build-unsigned-ipa.yml` uploads `Altboard-Canto-SideStore.ipa` using `actions/upload-artifact@v7` with `archive: false`, then publishes a direct IPA file in rolling GitHub Releases. This IPA is unsigned for development and requires SideStore re-signing; it is not an App Store-signed distribution.


## November 2 interaction correction

- The Latin spelling is always physically inserted into the host field, including English `OK` after Chinese `唔`.
- While composing, the candidate strip always includes the **actual case-preserved Latin token** (e.g. `OK`), even when no Chinese lookup matches. Tapping that token keeps the already-visible letters and closes suggestions. Pressing Space always clears suggestions and inserts a literal space.
- The Backspace intercept deletes a **single final romanized syllable** only for an exact dictionary match and a verified suffix. `gamyat` or `gamjat` → `gam` by deleting `yat` or `jat`; `gam1jat6` deletes `jat6`. Misspellings such as `gamyzt` fall through to standard single-letter deletion.
- After choosing `今日`, the composition is cleared, so the host's normal delete removes one Chinese character (`日`) at a time.
- The keyboard input diagnostic trace records only the type of action (space, candidate, syllable deletion), never any typed content.

- The candidate bar offers `OK` as a case correction when the user types `ok` or `Ok`, even after a Chinese character and even without Chinese dictionary matches. The literal typed form remains selectable separately. Pressing Space still keeps literal text.

## November 2 expanded candidate changes (review branch)

- Exact one-character Cantonese readings appear before prefix-only phrases.
- The candidate bar has a small right-side disclosure control. Its bounded
  four-column grid shows up to 200 distinct visible Chinese candidates.
- Untoned `ng` optionally surfaces `唔` as an input convenience; the source
  remains canonical `m4` and tone-specific lookup is not modified.
- This is review code only. Check keyboard height, overlay taps and Unicode
  input in the SideStore build before declaring it implemented on-device.
