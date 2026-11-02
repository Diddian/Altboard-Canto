# IPA iPhone test log

| Run | SHA | SideStore | Native Emoji globe | Swipe to/become/evermore | Cantonese | Haptics / AI / ASR | Result |
|---|---|---|---|---|---|---|---|
| Combined preview | pending | untested | untested | untested | untested | untested | pending |

**P0 symbol screenshot regression** (IMG_9698 / IMG_9699): Verify the
Alphabet and Symbols pages in Numbers and #+= modes. All ten middle-row
punctuation keys, ten top-row brackets and five bottom punctuation keys must
show a literal symbol. Press one of each type and confirm correct host text
insertion. Pay special attention to full-width 「」『』《》【】、！？，。;
a visually restored button is not enough without a working hitbox.

Next test both QWERTZ and QWERTY, horizontal swipe paths that revisit a prior
key (become, evermore), brush taper/cleanup, native globe/Emoji switching,
Cantonese scheme adaptation, Shift, held Backspace, cursor trackpad,
haptics, microphone/AI actions and VoiceOver.

Record exact build number/SHA, iOS version, expected and actual outputs
and a screenshot. No real-device checks are marked passed yet.
