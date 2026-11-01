# Altboard-Canto: offline Jyutping typing mode

## Implementation

Branch: fix/ios-keyboard-haptics-caps-20261102 (based on feat/cantonese-qwen3-offline-mvp).

### Existing keyboard retained

- Three existing modes: Microphone Only, Symbols, English Keyboard. Jyutping is a language choice inside the English Keyboard's geometry, not another tall keyboard.
- Default is QWERTZ and English; QWERTY is optional. English sentence capitalization is enabled on an empty field, after Return, and after full stop or question/exclamation punctuation. Users can turn it off.
- Reference screenshot 1320 x 871 px, inferred 3x: 45 pt key height, 6 pt horizontal gaps, 11 pt row gaps, 8 pt key corners, 23 pt SF regular letters, -1.2 pt visual vertical offset.
- English row side margins: top 6.67 pt, home row 28 pt, bottom row 6.67 pt; Shift/Delete 50 pt with 14.67 pt gap to adjacent letter. Altboard toolbar retains its mic, LLM and language buttons.
- Microphone Only mode fades ancillary controls and shows gray dictation status. English and Symbols modes keep the keys visible and rely on the existing microphone animation, with no gray final-preview text.
- Long press Latin letters to choose accented letters; key haptics are direct UIImpactFeedbackGenerator calls. Adjustable haptic strength and tappable preview are in Settings.

### Actual offline IME

1. Tap the EN / 粵 key in the alphabetic toolbar. English mode types normally. 粵 mode collects letters and tone digits into an uncommitted pre-edit buffer.
2. The app reads an indexed SQLite dictionary from the keyboard extension bundle. It does not call a web service, ASR, or the LLM on each key.
3. The toolbar displays candidates with Traditional Chinese text and tone-marked Jyutping. Tap a candidate or Space to commit; Return commits an active candidate, otherwise inserts a newline.
4. Backspace edits the composition first. When it is empty, it deletes the host's text. Unsupported characters or punctuation commit the current candidate, then insert the literal.
5. The input supports tone digits 1–6 from the number page, exact spelling, tone-sensitive matches, tone-free prefix matches, and initials abbreviations.
6. Local App Group storage records frequently selected candidates for subsequent ranking. If the dictionary has no match, raw romanization is preserved rather than lost.
7. Mic recordings share the existing dictation path and are independent from the offline typing dictionary. An external text-context change never silently commits the unfinished romanization.

### Data source and build

- Source: https://github.com/yuetyam/jyutping, pinned revision 16bda076094abd63e0961cdc49e2b08ab4e381a3.
- Input: Modules/Preparing/Sources/Preparing/Resources/jyutping.txt (word TAB romanization; example: 你好 TAB nei5 hou2).
- Verifies upstream Git blob SHA1 708236a9458ec933aa3d2b70aa372e613a7cc0b6, then generates JyutpingResources/jyutping.sqlite3 with indexes.
- The generated database is copied into SayboardKeyboard.appex by XcodeGen, and workflow checks its presence before publishing the IPA.
- The source project is CC0 and credits Rime-Cantonese (primarily CC BY 4.0). See docs/JYUTPING-DATA-NOTICES.md. ODbL maps are not included.

### Acceptance and verification

1. Run python3 scripts/build-jyutping-lexicon.py to pin and build the offline dictionary. Test that 你好 (nei5 hou2), 我 (ngo5) and 食 (sik6) are present.
2. Run swiftc -typecheck Shared/JyutpingComposition.swift Shared/SentenceCapitalization.swift; run the Swift smoke test in scripts/verify-keyboard-core.swift.
3. Run xcodegen generate and build scheme Sayboard for a generic physical iOS destination. Code signing disabled is acceptable for a SideStore IPA.
4. Verify the IPA includes Payload/Sayboard.app/PlugIns/SayboardKeyboard.appex/jyutping.sqlite3, keyboard extension and App Group capability request.
5. On an iPhone verify nei5hou2 -> 你好, ngo5 -> 我, sik6 -> 食; long press, repeat Delete, English case, QWERTZ/QWERTY, symbol keys, haptic slider/preview, voice button transitions and language toggle.
6. The workflow uploads a downloadable ZIP artifact to each Actions run and publishes an unsigned .ipa directly in the rolling development GitHub release. SideStore must re-sign it.

## Upstream feature-parity roadmap

The integrated keyboard does not import the full yuetyam CoreIME implementation. Its upstream current toolchain (Xcode 27 / Swift tools 6.4) is above this project's Xcode 26.2 build. The following are separate features, not claims of current parity:

1. Compound segmentation and partial-word commits: integrate the proven upstream segmenter or write test-driven segmentation so multi-syllable mixed input can keep an unconsumed suffix.
2. More colloquial / fuzzy romanization and habitual spelling, including candidate rank tuning against Hong Kong Cantonese usage.
3. Candidate grid, reverse lookup (Cangjie/Pinyin/strokes), Hong Kong/Taiwan character variants and simplified conversion with separate data-license checks.
4. Personal dictionary export/import, reset, context-sensitive learning, and data migration tests.
5. Benchmark lookup latency, startup memory, accessibility, orientation, iPad and tiny keyboard heights on devices.

These features may improve parity but are not required to type Jyutping offline using the new alphabetic keyboard.
