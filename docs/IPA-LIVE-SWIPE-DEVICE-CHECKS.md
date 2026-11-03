# iPhone acceptance — Live Dictation, Swipe and Settings (after #72)

Only a successful unsigned IPA build from main qualifies for installation.
The existing successful #72 IPA remains the rollback baseline.
Do not infer device behavior from Xcode compilation alone.

## Stop-ship regressions

1. Open Altboard History test field with no text: the X button is
   accessible, clears the field and dismisses the keyboard in one action.
2. Confirm ordinary EN/DE/Cantonese tap typing, Globe/Emoji, delete and
   long-press umlauts still work with Swipe off.
3. Settings opens one main scroll, in this order: Dictation; Speech &
   Languages; Keyboard; Text & AI. Models, corrections, diagnostics and
   History/Storage still open their own destination when requested.
4. With Qwen3-ASR 1.7B downloaded, enable Live Dictation, enable Active
   Session, place cursor in an EMPTY test input, press microphone and
   speak at least 12 seconds. Text must appear DURING recording, not
   only after Stop. If it does not: Help > Diagnostics shows live
   recognizer loading/status and the user can still Stop & Transcribe.
5. Repeat in Notes and ChatGPT, both empty and nonempty fields. Confirm
   partial updates append exactly once, no loss of typed prefix, no
   duplicate final transcript. Moving focus to another field must not
   insert any partial or final text in that new field. Cancel must not
   erase unrelated text. Test selected translation/AI cleanup; those
   operations may still complete after Stop.

## Swipe and spelling

6. Use QWERTZ then QWERTY; Swipe: you, not, actually, penetrate,
   strange, tight, your, and an intentional loop/crossing.
7. In ChatGPT, Swipe 30 words consecutively and verify the translucent
   brush stroke still paints every time. Repeat inside History and Notes.
8. Type somepeolpe; the candidate strip offers **some people** as a
   selectable correction but NEVER replaces text automatically.
   Type rapidly; second and third suggestions should change without
   fading to blank between individual keystrokes.
9. Swipe one word, then press Delete ONCE. The committed word and its
   automatically added space should disappear together; ordinary
   typed text still deletes one character per tap. Test caret movement
   before Delete to ensure unrelated text is untouched.
10. Hold A, U, O to access both secondary ?123 symbols and umlauts via
    the popover. Verify small condensed hint on the upper-right of each
    letter and condensed A on the space bar; no visible key sizing changes.
11. Settings > Help > Diagnostics > Swipe & Touch Counters: observe
    anonymized swipe counts, candidate rejects, touch learning and reset.
    Adaptation should require accumulated near-boundary Delete/adjacent
    repair evidence; it should never autocorrect or store raw touch paths.

## Meetings, performance and privacy

12. Meeting Record audio/15-minute grouping must still work; do not
    require a full 2-hour test before first short QA, but record gaps
    or lags at segment boundaries.
13. Check model cold start time, first live word delay and sustained
    updates on iPhone. Offline Qwen3-ASR uses short sequential ONNX
    decodes rather than true token-streaming. A 3-second chunk can take
    longer than 3 wall-clock seconds to infer.
14. Confirm English frequency corpus and third-party attribution ship
    inside SayboardKeyboard.appex; no network request is made on phone.
15. If serious regressions appear, disable Live Dictation/Swipe/Touch
    Learning or restore last working #72 SideStore IPA.

No user typing, host context or raw swipe traces may be included in logs
or uploaded from diagnostics.
