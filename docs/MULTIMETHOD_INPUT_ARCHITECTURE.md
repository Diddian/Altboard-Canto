# Multimethod Input Architecture

Altboard's keyboard has one touch system and one candidate-presentation layer.
Input methods are language-scoped adapters, not separate keyboard extensions.
This contract supports multiple spellings, code-table versions, and future
language-specific methods without conflating unrelated writing systems.

## Language and mode registration

- `InputMethodDescriptor` identifies `languageTag`, stable `identifier`,
  localized display title, and compact key label. `InputMethodCatalog`
  returns the descriptors enabled by the selected spoken languages.
- Today only `yue` registers methods: `yue.phonetic`, `yue.quick`,
  `yue.cangjie`, `yue.stroke`. The visible switch cycles 拼 → 速 → 倉 → 筆.
  Selecting `zh` alone does **not** expose these Cantonese methods.
  Chinese punctuation policy is independent from method registration.
- `SharedKey.keyboardChineseInputMode` persists the active Cantonese method
  in the App Group. It does not change output-language translation preferences.
- The same `AlphabeticKeyboardLayout` renders the toolbar, candidate strip,
  candidate expansion, bottom row, Globe, microphone, and AI controls. Stroke
  replaces only the letter grid. UIKit remains the sole owner of alphabetic
  touches; SwiftUI controls retain accessibility actions.

## The shared lookup contract

Each method normalizes its input to a **method-specific canonical code**,
looks up offline indexed candidates, deduplicates visible words, scores exact
matches ahead of prefixes, and learns only from explicit selection. A
candidate selection must be attached to the currently active composition;
changing mode, focus, or cursor invalidates the old composition without
deleting unrelated host text.

| Method | Canonical representation | Lookup sources | Preference evidence |
| --- | --- | --- | --- |
| Cantonese phonetic | Jyutping-linked syllable code with derived untoned indexes | Jyutping, Yale, Sidney Lau in `jyutping.sqlite3` | Explicit word selections; spelling-system preference only for distinguishable aliases |
| Quick | Lowercase QWERTY/QWERTZ letters, max 2 | Third- and fifth-generation Fcitx5 Quick tables | Word count; generation only for unambiguous selections |
| Cangjie | Lowercase letter code, max 6 | Third- and fifth-generation Fcitx5 Cangjie tables | Word count; generation only for unambiguous selections |
| Stroke | Sequence of five stroke classes, max 64 | Fcitx5 Stroke5 and Rime Stroke in `chinese-shapes.sqlite3` | Word count and explicitly selected **stroke-prefix + word**; no source preference |

Cantonese phonetic typing immediately inserts literal Latin text into the
host; candidate selection replaces only a verified suffix. Shape/stroke
compositions are buffered until the user selects a candidate. Never
generalize these host-writing rules to a different method without an
explicit composition contract.

## Universal stroke normalization

The physical keys always mean 横（一）, 豎（丨）, 撇（丿）, 點/捺（丶）,
折（乛）. The stable internal code is currently the Fcitx5 key notation.
These symbols are internal implementation details, not a source selector.

| Stroke class | Rime Stroke raw code | Fcitx5 Stroke5 / internal code |
| --- | --- | --- |
| Horizontal | `h` | `m` |
| Vertical | `s` | `/` |
| Left-falling | `p` | `,` |
| Dot / right-falling | `n` | `.` |
| Bend | `z` | `n` |

`scripts/build-chinese-shapes.py` preserves each upstream row's identity
and translates Rime `hspnz` sequences into `m/,.n` before insertion.
Both sources live under `method='stroke'`, `variant=0`; `source` keeps
provenance for audit. Distinct codes for one word remain valid alternatives.
Identical visible words are merged during candidate lookup, not at the
expense of their original code rows.

Rime may provide longer stroke sequences than Fcitx5. Do not truncate them
to five strokes or automatically commit a word at five keys. For performance,
the builder precomputes bounded top candidates for the first 1–3 strokes
into `stroke_prefix`; longer codes use indexed range search. Queries and
the expanded candidate grid have bounded result counts.

Stroke preference is **not** a classifier for which source the user favors.
Selections increment bounded counts for `canonicalTypedCode|selectedWord`.
The same source-neutral memory works when two sources contain the same word
and code, or when one word is written with different stroke sequences.
Source differences alone never justify learning a preference.

## SQLite and preference boundaries

- The keyboard opens compiled SQLite read-only and makes bounded queries.
  Runtime typing requires no network, Rime runtime, Fcitx runtime, or
  additional keyboard gesture recognizer.
- `ChineseShapeDictionary` preserves bounded aggregate App Group counts.
  Word counts support all shape methods; code-specific counts refine stroke
  ordering. Third-/fifth-generation biases are separate and only updated
  for unambiguous Quick/Cangjie choices.
- `JyutpingDictionary` and `CantoneseSchemePreference` retain the
  existing phonetic indexes and selection logic. Romanization schemes are
  pronunciation aliases, **not** Mandarin Pinyin, and must not be mixed
  with phonetic systems from another language.
- Never persist full host context, raw typing traces, transcripts, or
  credentials to infer preferences. Store at most bounded method/code/word
  aggregate counts and reset active composition on mode or context changes.

## Data provenance and redistribution

- `fcitx/fcitx5-table-extra` revision
  `dbc7154a7f0b9fc04313160ae8066ed4d8cbc446`: bundled pinned
  `cangjie3`, `cangjie5`, `quick3`, `quick5`, `stroke5` data.
  Its README declares the **data files** Public Domain; the program code
  is GPL-3.0-or-later and is **not** embedded.
- `rime/rime-stroke` revision
  `1e8fff9b9494ddec23b0cbc526bcfd8171a6fd48`, upstream Git blob
  `5a4a49a825d40d85709b197caade546f192a5bde`, supplies
  `stroke.dict.yaml`. It is redistributed as normalized data under the
  upstream **LGPL-3.0** terms. The keyboard bundle includes
  `RimeStrokeNotice.txt`, `RimeStrokeLicense.txt`, and
  `RimeStrokeGPLv3.txt`.
  Upstream sources and the conversion generator remain publicly available.
- The build verifies the pinned upstream Git blob SHA before generating
  SQLite. A source change needs its own provenance and licensing review.
  An unavailable or mismatched upstream source must fail the dictionary
  build rather than silently substitute unverified rows.

## Adding another language

1. Register a new method family under its language tag and a stable,
   namespaced identifier; do not reuse `yue.phonetic` for `zh`.
2. Define its visible keyboard arrangement, canonical code, parser,
   composition/host-write policy, and explicit-choice attribution rules.
3. Add independently licensed, pinned dictionaries and offline indexes;
   retain source variants for diagnostics and exact/prefix querying.
4. Reuse the candidate strip, expansion, persistence bounds, and host-safety
   gates. Register the method only after its input and output paths exist.
5. Add deterministic tests for registration gating, normalization,
   candidate deduplication, and preference changes before producing an IPA.

For example, future Mandarin `zh` registration could offer Hanyu Pinyin,
Bopomofo, and additional shape methods. Mandarin readings require separate
indexes and language-specific normalization, while their candidate UI and
selection-based ranking contract can be shared. None of those methods is
presently registered or asserted to work.

## Source ownership

- Mode registry / stroke glyph mapping: `Shared/ChineseInputMode.swift`
- Cantonese phonetic: `SayboardKeyboard/JyutpingDictionary.swift`
- Shape/stroke lookup and learning: `SayboardKeyboard/ChineseShapeDictionary.swift`
- Candidate presentation and composition: `SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift`
- Stroke layout: `SayboardKeyboard/Views/ChineseStrokeGrid.swift`
- Offline database compilation: `scripts/build-chinese-shapes.py`
- Deterministic checks: `scripts/test_chinese_shapes.py`,
  `scripts/verify-chinese-input.swift`
- Physical iPhone packaging: existing
  `.github/workflows/build-unsigned-ipa.yml`
