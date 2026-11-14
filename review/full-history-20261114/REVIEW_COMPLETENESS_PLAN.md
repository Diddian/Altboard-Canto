# Altboard-Canto — X9–X15 Complete Review and Acceptance Plan

**Reviewed production baseline:** `main@c1b3a1082f8be5af0e10ea85fad19e27e74f1b6b`. **Latest Actions:** [Build #236](https://github.com/Diddian/Altboard-Canto/actions/runs/43629599094), completed success; `Altboard-Canto-TEST.ipa` artifact ID `14127992826`, 80,455,514 bytes. **Physical SideStore/iPhone acceptance has NOT RUN.** This is a Development TEST IPA, not a Release Candidate.

**Repository rules:** Single production source of truth is `main`. Review records belong on `review/full-history-20261114`; never merge review files into `main`. Do not create PRs, additional IPA workflows, speculative replacement owners, manual QA documents on production `main`, or publish raw typing, audio, transcripts, credentials or host text.

## What the X0–X7 'complete' labels establish

X0–X7 audited the historical source at `ed2c4ede05567f3f63d2979ade81040c8fe799ad`. They created eight stage records, diagrams and a complete **file inventory**, but did not complete all whole-file reviews or device/runtime acceptance. Historical baseline: **577 current files = 165 reviewed + 166 excluded + 246 not reviewed**, and **14 historical-only paths not reviewed**. Build #236 adds exactly one newly source-inspected Swift test file, so current `main` has **578 files**. Source-reading a Swift `@Test` is not executing it.

The requested remainder is **426 uniquely identified files**: 246 current previously unreviewed, 166 previously excluded and 14 historical-only. All 426 are assigned once in `review-queue.json`. A queue entry is **not** evidence of review. The queue's P0/P1/P2 is provisional review order, not a defect severity rating.

## Stages and ownership

| Stage | Assigned files | Scope | Stop condition |
| --- | ---: | --- | --- |
| **X8** (still open) | Existing repair slice | Fix confirmed root causes on `main`, verify acceptance and provide TEST IPA | >=90% *verified, predeclared* case weights per implemented task, all mandatory/critical cases pass; physical device gate remains separate |
| **X9** | **65** | Core/native/shared runtime, model, storage, host, audio, persistence, security | Whole-file code review + immediate callers + state/failure/test oracle for each file; blockers documented |
| **X10** | **77** | UI, keyboard, gestures, feedback, onboarding, Settings, data screens, accessibility | Inspect all 77 files; prove expected interaction contract in source, identify device-only cases without declaring them green |
| **X11** | **104** | Native unit tests, scripts, entitlements, test harnesses, build safety | Inspect each file, map each test to actual workflow execution, correct source assertions vs runtime tests; record unrun native tests |
| **X12** | **166** | Re-open **all previously excluded** documents, binaries, localization, licenses, assets and data | Type-appropriate evidence for each; no blind re-exclusion. 90 MP4 tutorial files need content/provenance evidence where feasible, otherwise explicit `reviewed_limited` or `blocked` |
| **X13** | **14** | Historical-only deleted/renamed files and Build #1–232 history blind spots | Recover actual historic source/commit; trace removed behavior to current owner or bounded retirement decision |
| **X14** | N/A | Fresh-context independent reconciliation, source drift, findings, executable CI and iPhone evidence | All queued files defensibly disposed, high/critical defects addressed or visibly blocked, >=90% verified case weight + every mandatory case |
| **X15** | N/A | Durable archive and **approval-gated** review-branch cleanup | User explicitly approves deletion after technical summary is archived; no automatic evidence erasure |

**Scheduling:** X9–X13 are read-only source audits. They may run sequentially while X8 awaits user-device evidence. X14 requires X8 and X9–X13 reconciled. X15 cannot run automatically. All production repair changes remain owned by X8 and need their own acceptance matrix and authorized, current-HEAD update.

## High-priority, deduplicated findings

Keep `findings.json` as the issue register. Do not open a new finding if an existing F-ID explains the same root cause.

- **P0 host correctness and recoverability:** F-0018, F-0019, F-0020, F-0021, F-0022, F-0023, F-0024, F-0025. Check exact host field, session and document epoch; no duplicate or foreign-field insertion; durable ASR/LLM handoff, clipboard only after deliberate user action, release original result only after checked cleanup. The unmerged `fbbd719f` copy-safety candidate is *not* on `main`; review, do not layer it blindly.
- **P0 user-data integrity:** F-0031 and F-0032. Malformed History index must not destroy new audio; Delete All must verify orphan audio deletion; failed file removal cannot silently report success.
- **P0 test evidence:** F-0001 brittle source-string assertions; **new F-0039:** existing workflow compiles the iOS target without executing the native `SayboardTests` target. A green IPA alone cannot verify the `LiveInsertionReceiptTests.swift` `@Test` cases.
- **P1 model/install integrity:** F-0027, F-0028, F-0029, F-0038. Migration retry, corrupted background download metadata, failed deletion, immutable source revision and checksums.
- **P1 input/lifecycle:** F-0004, F-0007–F-0015, F-0030, F-0033. Haptics/globe, first microphone, host liveness, accessibility and All Data scope. F-0008/F-0013 and other hypotheses need discriminating tests rather than unsupported fixes.
- **P2 multilingual/output:** F-0026, F-0034, F-0035. Short wrong-language translations, German Swipe physical key geometry, and Cantonese continuation after compound phrases.

## Evidence required for every queued file

1. **Pin source and provenance.** Recheck `main` HEAD/Actions, compare blob SHA with the queue, and inspect exact historical commit for removed files. If `main` advanced, recheck affected owners before accepting earlier evidence.
2. **Read the complete relevant content.** For Swift/ObjC/test/scripts: owner, caller, state, side effects, stale/retry/cancel and privacy. For design/data/localization: parse contents, keys, licensing, resource relationships and user-facing consequences. For binary/video assets: inspect available file metadata, attribution and actual media only where tool access permits. Do not treat file extension as exemption.
3. **Use two complementary lenses.** **Untangle Dev** tests canonical ownership, hidden links, redundant owners, special-case paths. **Manual OCR-style review** tests correctness, error boundaries, data loss, concurrency, accessibility and test adequacy at exact file/line. Alibaba Open Code Review CLI **NOT RUN**; do not use a remote paid model or upload private source without permission.
4. **Record objective evidence.** Mark `reviewed`, `reviewed_limited` or `blocked` with exact SHA, file/line or binary evidence, inspected caller, risk and test oracle. Mark `pass`, `fail`, `not_run` for tests; source inspection alone cannot assert iPhone behavior.
5. **Prioritize without duplication.** Check `findings.json` first. Add a new F-ID only for a distinct verified root cause or clearly labelled hypothesis. State severity separately from provisional file-review priority.
6. **Checkpoint atomically.** Update `review-queue.json`, `coverage.json`, `findings.json`, `stages/Xn.json`, `manifest.json` with current review HEAD lease. No build or IPA for documentation-only changes.

## Build #236 evidence and open gates

- Verified **success** at SHA `c1b3a1082f8be5af0e10ea85fad19e27e74f1b6b`, run `43629599094`, uploaded `Altboard-Canto-TEST.ipa` (artifact ID `14127992826`). App Group packaging checks passed.
- Verified in the workflow: Python source-contract tests and standalone Swift verifiers; Xcode **build** for generic iOS destination. **No `xcodebuild test` execution of native `SayboardTests`.** Treat new Swift Testing `@Test` cases as *compiled or source-reviewed, not executed*.
- **Not run:** physical iPhone SideStore test of initial Globe/keyboard, haptics, Live Dictation re-entry, AI original-field insertion, clipboard recovery, native playback finish, failed migration/download, corrupt History and Conversation transfer.
- Preserve older usable IPA, no RC claim. Export redacted structured diagnostics only after deliberate user action if on-device failure occurs.

## Resume in Chat Mode

Read `manifest.json` -> `stages.json` -> `review-queue.json` -> active `stages/Xn.json`. Check fresh `main` and Actions first. Start X9 by fetching a P0 core file and its immediate caller; continue until the scoped stage is complete. Do not restart X0–X7, invent scores, duplicate recovery code, or remove the evidence branch. In case of context limits, save the *in-progress current stage* to GitHub and resume that stage.
