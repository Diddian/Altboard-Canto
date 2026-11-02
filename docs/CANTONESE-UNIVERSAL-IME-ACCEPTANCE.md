# Universal Cantonese Input — review acceptance

Three indexed spelling systems feed a single offline candidate engine without asking which one users know. For the same lexicon entry, `keoi / keui / kui` should show 佢, `zeoi / jeui / jui` should show 最, and `jyun / yun / yuen` should show 完. Alias suggestions are not automatic text replacements. Tone digits remain strict.

## Implemented in review branch
- Direct offline indexes: Jyutping, Yale, Sidney Lau
- No visible scheme picker; legacy stored values remain harmless
- Bounded `mm` and `ng` shorthands for 唔, without hiding genuine ng candidates
- Sidney Lau syllable deletion rules and isolated tests
- Resource placeholder exclusion for the last CI failure

## Not yet verified or incomplete
- A successful Xcode/SideStore IPA run after this patch
- iPhone keyboard typing, speed, memory, and host-field safety
- Per-syllable mixing in long unspaced phrases
- Robust multiword typo and lazy-sound recognition
- Production-grade frequency/context ranking and user-selected orthography
- Full Emoji rendering/search, Chinese punctuation, mic and AI editing regression testing

Run 41528118833 failed at Xcode project build preparation: two resource directories each contributed a `.gitkeep` copied into `SayboardKeyboard.appex/.gitkeep`. Run 41528033614 was cancelled when superseded. Neither represents a verified Swift source compiler failure.
