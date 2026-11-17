# DRAFT — X16–X22 repair intake

**Draft only. No development task is approved or complete.** The existing X0–X15 stage evidence is retained without changing its completion claims. The existing X8 source repair and X14 device/acceptance gaps remain open, and X15 archive cleanup is still blocked.

**Baseline to test:** [unsigned Development IPA #248](https://github.com/Diddian/Altboard-Canto/actions/runs/44143269130), `main@830480ad94f94e2dfe27af2b35350384e4942771`. CI completed success and artifact `Altboard-Canto-TEST.ipa` exists (artifact 14357795009). **No SideStore/iPhone result has been verified here.** Later tests must record their own exact build/SHA.

**Canonical existing findings:** `findings.json` (F-0001–F-0050). **Canonical X8 case weights:** `acceptance.json`. X16–X22 are prospective owners only, not a second issue tracker or authorization to reapply old patches.

## Proposed stages

| Stage | Priority | Repair slice | Initial scope |
| --- | --- | --- | --- |
| **X16** | intake | Draft intake: iPhone findings and approval decisions | Await device observations |
| **X17** | P0 | Host-field, microphone and result recovery safety | 13 existing F-IDs |
| **X18** | P0 | History, persistence, deletion and export integrity | 6 existing F-IDs |
| **X19** | P1 | Cantonese ASR, models and resource reliability | 9 existing F-IDs |
| **X20** | P1 | Keyboard lifecycle, touch and accessibility | 15 existing F-IDs |
| **X21** | P1 | Multilingual typing, translation and text integrity | 5 existing F-IDs |
| **X22** | gate | Executable regression gate and development acceptance | Executable evidence and acceptance |

- **X16 first:** add new user-observed failures below, with reproducible conditions; then decide scope in Grill Me. Do not assume every historic F-ID still reproduces.
- **X17–X21:** before implementing, check live code, existing fixes, diagnostics and negative-case tests. Reuse current owners; no duplicate bridges, observers, data stores or download paths. Production edits require separate approval and resolution of the existing X8-only ownership rule.
- **X22:** execute only the approved regression cases, verify native test execution and the single unsigned IPA workflow. Each implemented task needs at least 90% predeclared evidence-backed acceptance weight and every mandatory/critical case. iPhone acceptance is separate; no RC claim or X15 deletion.

## User-added findings (editable)

Add one new row per *distinct observed problem* after testing #248. Use an ID `U-001`, `U-002`, etc. Reference an existing `F-XXXX` if it matches; do not create another root-cause record for the same defect. **Use synthetic examples only. Never commit actual typed text, host content, recordings, transcripts, private device logs, credentials, or personal identifiers to this potentially public review branch.** Keep exported diagnostic JSON private until deliberate, redacted sharing.

| User ID | Related F-ID or new | Build/SHA | Area and reproduction (non-sensitive) | Expected vs observed | Severity (provisional) | Evidence / state |
| --- | --- | --- | --- | --- | --- | --- |
| _Add after SideStore test_ | — | #248 / `830480ad94f9` | — | — | — | `unverified` |

For a reproducible issue: include platform/iOS version when relevant, whether it is host app or keyboard, whether it occurs cold/warm or after reentry, and whether retry/Stop/restart safely recovers. Avoid raw user data. A user report is evidence of observed behavior, not proof of root cause.

## Source-patched; verify rather than blindly repair

- `F-0043`: punctuation apostrophes/decimal rendering, patched in `main@830480ad94f94e2dfe27af2b35350384e4942771`.
- `F-0048`: icon-only History/Model accessible names, patched in `main@830480ad94f94e2dfe27af2b35350384e4942771`.
- `F-0050`: Chinese tutorial fallback, patched in `main@830480ad94f94e2dfe27af2b35350384e4942771`.
- Earlier X8 ASR/LLM recovery work (`F-0018`–`F-0025`) and model integrity changes: re-evaluate the current owner before touching source. Device/runtime acceptance is not established by CI.

## Decisions reserved for Grill Me

Approve the X16 findings and priorities before promoting any X17+ stage; determine must-fix versus deferred behavior, manual device acceptance, and whether to amend the old X8-only production repair ownership rule. X15 archival cleanup is independent and never implicit. All stages remain `draft` until a separately authorized implementation turn.
