# Experimental combined IPA — physical iPhone checks

Build only from `main` with the existing `.github/workflows/build-unsigned-ipa.yml`.
A successful compile is not evidence of runtime behavior. Keep the previous
known-installable #70 IPA available for rollback.

## 1. Safe starting state

- Use SideStore to install the new IPA. Confirm the app and keyboard show the
  same build SHA in diagnostics.
- Confirm ordinary tap typing, Cantonese composition, Emoji/Globe,
  backspace/long-press, Settings Active Session, audio recording and final
  transcription work **before enabling any experimental toggle**.
- Under Settings > Dictation, leave both Live Qwen3 Dictation and Meeting Record
  OFF unless testing. Under Keyboard > Swipe & Touch Diagnostics, leave
  Learn Touch Boundaries OFF unless testing.

## 2. Experimental live dictation

- Select downloaded Qwen3-ASR 1.7B; enable Live Qwen3 Dictation.
- Activate Active Session, return to Notes/ChatGPT, tap the normal microphone,
  and say `It's very strange`, then a longer Cantonese/English/German sentence.
- Record the observed time until the first provisional text and successive
  updates. The current ONNX path decodes consecutive ~3s chunks; this does not
  certify native token-by-token streaming or guaranteed 3s wall-clock latency.
- Stop: the final text must replace the marked provisional text **once**, with
  no duplicate, lost leading space or overwritten unrelated input.
- Cancel within 1.3s or after partial text: the experimental text must not
  remove older user-entered content.
- Change host field/cursor during recording: never overwrite a different field;
  note if the provisional marker remains in the previous field.
- Disable experimental Live and repeat standard Stop & Transcribe. Test with
  translation or AI cleanup enabled: existing final-only behavior must remain.
- Test iPhone lock, switching apps, no model, microphone permission denied,
  offline mode, memory pressure and extended recording.

## 3. Swipe + adaptive hitboxes

- Enable Swipe Typing. Try `I think that's very strange`, `penetrate`,
  `tight`, `become` and `evermore` in Notes, ChatGPT and in-app test field.
- Swipe with self-intersections, long backtracking paths, QWERTZ and QWERTY;
  confirm a candidate appears when known and no ghost letter is inserted.
- Swipe at least 30 times without leaving ChatGPT. Confirm a visible translucent
  trail on **each** swipe, not just the first several. Compare dark/light mode.
- Open Keyboard > Swipe & Touch Diagnostics, enable counters, refresh after
  trying valid/invalid/cancelled gestures. Counts must never include raw
  typing, host text or stored stroke paths.
- Enable Learn Touch Boundaries. Repeat **deliberate** near-border mistaken
  tap -> Delete -> adjacent correction at least five times, then test hit
  boundaries. Single mistakes, unrelated deletion, distant taps, swipe and
  cursor movement must not cause broad drift.
- Reset Diagnostics & Touch Learning, then confirm neutral geometry returns.
  Inspect tap latency, accents, Delete hold, Space cursor and VoiceOver.
- No autocorrection should change a completed word without explicit selection.

## 4. Meeting Record experiment

- Under Dictation enable Meeting Record and open Meeting Recordings.
  Select Qwen3-ASR 1.7B and test a 30–60 second recording with English,
  Cantonese and mixed speech. Verify saved audio and transcript exports.
- Test a continuous meeting crossing 15:00 and 30:00. The UI must keep
  recording, with one meeting folder, correctly ordered parts and one
  combined transcript. The current rotation is time-based and should be
  verified against the recorded audio timestamps for any gaps.
- A real uninterrupted 120:00 meeting should yield **eight nonempty
  15-minute files** in one meeting, not eight separate meeting records.
  No ninth empty audio part should be retained.
- Test Stop, cancellation through interrupted audio route, locked screen,
  backgrounding, incoming call/Bluetooth changes, low storage and re-opening
  the meeting. Current Qwen ONNX decode may fall behind real time.
- Test retention and storage externally; meeting folders are independent
  from ordinary one-off Dictation history. No network or silent audio upload.

## Known experimental limitations

- The current Qwen3 SherpaOnnxOfflineRecognizer decodes full short chunks,
  not confirmed native streaming. First-text latency depends on warm-load,
  CPU speed and background execution.
- The touch area learner uses anonymous boundary counters from explicitly
  corrected adjacent taps. It cannot reliably infer every typo's intent.
- The Swipe dictionary is expanded only modestly here, not yet a full
  licensed frequency-ranked EN/DE corpus.
- The meeting recorder rotates files by main-loop elapsed time, not exact
  audio sample frame position. Long lock-screen/thermal tests are required.
- Failed/cancelled inferences may leave a partial transcript; saved audio
  remains the recoverable primary record.

If any serious typing regression occurs, disable the experimental settings
or re-install the previous usable #70 SideStore IPA.
