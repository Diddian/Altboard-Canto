# Altboard-Canto temporary full-history code review

**Technical work area only; remove it at X9.** Public GitHub branch `review/full-history-20261114`, folder `review/full-history-20261114/`. No source edits or unsigned IPA builds belong on this review branch. Production source is `main`; pinned initial source is `ed2c4ede05567f3f63d2979ade81040c8fe799ad`.

## Start / stage routing

In a **new ChatGPT Chat Mode chat**, use the single command: **「Altboard-Canto：按 `review/full-history-20261114` 嘅 `review/full-history-20261114/manifest.json` 開始 X0。」** Replace X0 with the stage listed in `manifest.json`. Load `stages.json` and only that stage's `stages/Xn.json`. The stage file is the durable checkpoint; a new chat must not rely on prior conversation memory.

## Workflow

1. Check `main` HEAD and recent Actions; pin the code SHA and compare drift with earlier results. Read the stage's live code and tests from `main` at a fixed SHA.
2. Apply two **distinct** lenses: Untangle structural state/owner graph, and line-level **manual OCR-style** file/defect review. Alibaba Open Code Review CLI is **NOT RUN** merely because the skill is available.
3. Record technical evidence in `coverage.json`, deduplicated root-cause findings in `findings.json`, and labelled observed/proposed edges in `diagrams/Xn-*.mmd`. Record exact file, symbol or line, source commit, scenario and test oracle.
4. Update `stages/Xn.json` and `manifest.json` in one Git commit on this review branch. `Xn=complete` only after its stop gate. Next worker begins `X(n+1)`. On Chat context pressure, commit checkpoint with Xn=`in_progress` and resume **the same Xn** in a fresh chat.
5. X0–X7 audit only; X8 may commit small evidence-backed fixes to `main` and run existing `.github/workflows/build-unsigned-ipa.yml` **once when required**. X9 only cleans the temporary review folder after full acceptance.

## Immutable restrictions

Do not copy private ChatGPT Project Sources into this public repo. No raw typing, transcript, audio, passwords, host text or personal identifiers. No documentation-only IPA. No PR, no speculative whole-repo rewrite, no force push, no duplicate owners, no subjective acceptance percentages. Do not re-run 232 iOS builds. Earlier commits can be reviewed through bounded compare windows and Git file history. A passing CI artifact is **not** physical iPhone acceptance.

## Data ownership

- `manifest.json`: ONLY phase status and next stage.
- `stages.json`: predeclared stage scope, expected outputs and stop conditions.
- `stages/Xn.json`: exact stage evidence, reviewed SHA, output paths and next-step gates.
- `history-index.json`: Actions and historical change mapping.
- `coverage.json`: authoritative source-file and historical-diff accounting.
- `findings.json`: root-cause issue register, never duplicate an issue under another name.
- `acceptance.json`: predeclared real behavioral tests, evidence and strict per-task >=90% decision.
- `diagrams/`: temporary technical state graphs with source/status labels.
- `cleanup.json`: X9 disposal contract.

If `main` advances, do not silently treat a previous source review as current. Preserve evidence and create a scoped drift review, without moving review branch back to main.
