# Altboard-Canto — Chat Mode full-history review

**Production source:** current `main` HEAD. **Review records:** `review/full-history-20261114`, directory `review/full-history-20261114/`. Latest verified TEST IPA at this checkpoint: Build #236, SHA `c1b3a1082f8be5af0e10ea85fad19e27e74f1b6b`, GitHub Actions run `43629599094`. **Physical iPhone acceptance: NOT RUN.**

## Start / resume

1. Read `manifest.json` and `stages.json` on this review branch. Then read `REVIEW_COMPLETENESS_PLAN.md`, `review-queue.json` and only the selected `stages/Xn.json`.
2. Check live `main` HEAD, relevant `docs/TASKS.md` and recent unsigned IPA Actions. Resolve drift; never use dated builds as live source.
3. For X9–X13, choose P0/P1 queued files in that stage. Read the complete source at exact SHA and relevant caller/consumer. For previously excluded assets, inspect meaningful media/metadata/localization/license evidence; explicitly state if full binary contents were not inspected. Historic paths require an actual old commit.
4. Perform **both** Untangle Dev ownership/state inspection and manual OCR-style diff/correctness review. The Alibaba OCR CLI has NOT been run. Avoid paid external tools and do not publish private data.
5. Record `reviewed`, `reviewed_limited` or `blocked` in the queue with exact evidence, test oracle, uncertainty and status `pass/fail/not_run`. Deduplicate new findings with `findings.json`; link to verified source and priority.
6. Commit `review-queue.json`, `coverage.json`, `findings.json`, `stages/Xn.json`, `manifest.json` on this **review branch** with expected HEAD checks. The original X0–X7 remain source-audit checkpoints, not device acceptance.
7. X8 retains responsibility for authorized production repairs and per-task >=90% verified acceptance, plus required device checks. X9–X13 may review source sequentially while X8 is open. X14 reconciles all evidence; X15 preserves records unless the user explicitly approves their cleanup.

**Next stage:** Follow `manifest.lifecycle.next_stage` (X9 at this checkpoint). Preserve unfinished stage state in GitHub before changing chats. No PR, force-push, duplicate IPA workflow, documentation-only IPA, or auto-cleanup. Keep the previous usable IPA.

**Data:** This review branch may be public. Never commit raw typing, host text, user audio/transcripts, credentials, sensitive identifiers, or private Project Sources.
