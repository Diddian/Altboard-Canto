# QA second wave — verified scope and separate remaining gates

Branch: `review/qa-half-wave1-20261102`.
Base: `e9e6da27bf03482694d477ac902005260749161f`.
Feature IPA branches (untouched by this work):
- #63 successful `8c1d6b22ef55b30e7c52940374fc0f377924a37e`.
- #64 `feat/swipe-trail-emoji-native-parity-20261102`, separate IPA workflow.

## 1. Evidence inspected directly from actual Action #63 IPA

Downloaded the `Altboard-Canto-Unsigned-IPA` artifact from Action #63,
ID `13183217845`, as an IPA ZIP. Inspected
`Payload/Sayboard.app` and
`Payload/Sayboard.app/PlugIns/SayboardKeyboard.appex`.

| Fact | Result |
| --- | --- |
| App identifier | `app.sayboard` |
| Extension identifier | `app.sayboard.keyboard` |
| Both stamped SHAs | `8c1d6b22ef55b30e7c52940374fc0f377924a37e` |
| Both versions | `1.14.0` (build 22) |
| SQLite resource bytes | 36,384,768 |
| SQLite `PRAGMA quick_check` | `ok` |
| Unique entry rows | 185,717 |
| SQL indexes | `word`, `plain`, `compact`, `yale`, `sidney`, `initials` |
| `keoi`, `keui`, `kui` | each finds `佢` (canonical `keoi5`) |
| Emoji TSV bytes | 210,857 |
| Emoji entries | 3,963 unique rows |
| ZIP CRC | `testzip() is None` — archive integrity passes |

Package inspection is not evidence that the keyboard runs or its Emoji glyphs
render on the physical iPhone. The #64 IPA is a different unverified build.

## 2. Changes staged on the QA-only branch

- Python read-only `scripts/verify-ipa-bundle.py`: validates SHA,
  identifier, SQLite indexes/quick_check, 3- and 4-column Unicode emoji
  asset formats, row counts, and ZIP CRC; synthetic test cases for rejection.
- Canonical Jyutping/Yale/Sidney comparisons, SQL index plans, and distinct
  tone tests. Fix test fixture escape errors before CI execution.
- Emoji parser fixture regressions (qualified-only, dedup, ZWJ and skin tone).
  #64 owns the redesigned Emoji View. No conflicting QA UI changes are merged.
- Pure `ChinesePunctuationPolicy` looks at host text preceding cursor to
  choose 「 or 」 and avoids old toggle state after cursor movement. It is
  read-only and does not insert text on its own; quote behavior still needs
  native testing.
- Settings regression checks for legacy saved preferences, haptic strength,
  optional swipe and visibility; no settings migration or default reset.
- One-edit offline English/German candidate guard: exact known words should
  not receive speculative fallback replacements. No auto-replace or cloud.
- Known #63 compilation fix replayed to QA: `self.romanization` removed from
  touch-prediction code. Adds no touch recognizers or independent key owners.
- Pure Ubuntu QA workflow, **not** the unsigned macOS IPA workflow.

## 3. Run and acceptance

Offline QA runs on push to this QA branch alone:
`https://github.com/Diddian/Altboard-Canto/actions` — workflow
`Offline QA regression checks (no IPA)`.

Standalone package verification:
```sh
python3 scripts/verify-ipa-bundle.py /path/to/Altboard-Canto-SideStore.ipa \
  --expected-sha 8c1d6b22ef55b30e7c52940374fc0f377924a37e
```

Do not claim the QA code is iOS-compiled or device-tested from Ubuntu
policy tests alone. If the QA workflow fails, inspect the **first error** and
repair only the isolated branch. Preserve the last working IPA.

Outstanding: physical key hitboxes, touch event dedup, haptic/VoiceOver,
Cantonese context, Emoji iOS rendering (owned by #64), punctuation cursor
movement, Settings persistence UI, German word accuracy and performance.
Never merge this entire QA fork into #64 without conflict review.

Ordering: finish stable Swipe Beta -> common long Cantonese phrases and
per-syllable mixed Romanization -> experimental Live Transcription.
