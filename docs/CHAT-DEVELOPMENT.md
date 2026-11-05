# Current integration — 5 November 2026

The actual main checkout is based on build 123 (`d2fb55443e710ab492231073c9620de715f5eac9`)
with local UI changes: temporary Globe suppression, an active-swipe-only drawing
UIView, horizontal root-page navigation, one Output route inside AI Actions,
and icons on Customization and History & Storage. The canonical APP-STRUCTURE.json
and generated menu describe this local source. PWA_APP_DESIGN_GUIDE.md records
source observations and verification requirements. No new IPA, push or phone test
is implied. The ink-pad report remains unresolved. Original local documentation
is backed up outside the repository in the chat outputs/pre-integration-backup.

The following handoff is historical build-120 evidence; it is retained rather
than presented as verification of the current local changes.

---

# AltBoard-Canto: chat development handoff

Source baseline: `ba43523b2074c13fd17cf4c059c0fa56d3ecdd07` (main).
Verified IPA: build **120**, marketing version **1.14.7**, 5 November 2026.
This is a documentation update. It changes no app behavior and proves no phone fix.

## Read the right document

- `APP-STRUCTURE.json`: current navigation, settings ownership, conditions,
  source hashes and feature entry points.
- `SETTINGS-WORKFLOW-TREE.md`: readable menu, generated from that JSON.
- `KNOWN-ISSUES.json`: evidence, hypotheses, gaps and acceptance checks.
- `TASKS.md`: existing expansion backlog. Historical entries are not current UI.
- Root `AGENTS.md`: scoped instructions for repository work.

For chat mode without repository access, attach the JSON, menu and issue register
together. They describe the baseline above. Request current affected source and a
base-compatible patch before implementing; do not reconstruct source from prose.
If source is unavailable, return a clearly labelled proposal, not a claimed patch.

## Feature first, with a bounded consistency check

Chat development tends to concentrate on the visible page. Keep that focus, then
trace its connections before changing it. For example, an Output Key report needs
the customization preference, persisted key, toolbar consumer and preview; it
does not need a new settings hierarchy or a new inference engine.

For each requested change, identify:

1. The user action, expected result and actual evidence.
2. The existing owner and stored setting (when present).
3. The action/service and its keyboard or app consumers.
4. Adjacent preview, help text, diagnostics, localization and cancellation paths.
5. A focused check and any physical-device acceptance check.

Use the feature entry points in the JSON. Read affected files only. Broaden when
a named dependency or observed failure requires it, not as a standing whole-app audit.
For a requested UI audit, show the five biggest evidenced problems before edits.
For an ordinary bug, do not turn the investigation into an unsolicited redesign.

## Keep the menu current without asking the user to rewrite it

The JSON is the single documentation source for the menu. It is source-reviewed,
not an automatic Swift parser. The checker detects changes to its listed owners
and drift between JSON and Markdown. It does not prove runtime reachability,
absence of omitted routes, correct SwiftUI layout or smooth iPhone behavior.

After changing a listed owner, inspect its relevant routes and consumers. Update
the JSON nodes and that owner's SHA-256 only after review. Then run:

```sh
python3 scripts/check-app-structure.py --write
python3 scripts/check-app-structure.py --check
```

`--write` only renders the menu. It does not bless changed source hashes.
New routes require adding their owning files to the map. Conditional and dynamic
rows must retain their conditions; do not present every row as always visible.
The developer maintains this tree as part of the change, rather than asking the
user to supply it again. Detached files cannot enforce behavior in another chat.

## Current consistency contracts

- Navigation is **History / Meetings / Settings**. Model screens are reached from
  Settings → Speech & AI. Archived documentation that calls Models a tab is stale.
- Active Session belongs on Settings home. Dictation contains recording policies,
  live dictation and meeting enablement, not a second session toggle.
- One Keyboard section: Keyboard Type; conditional Microphone Layout or Key Order;
  collapsed Customization; visible Preview. Haptics is a toggle, with no user
  strength or haptic test submenu in Customization.
- History & Storage is collapsed under App. Its current categories are Voice Notes,
  Meetings and combined Corrections & Suggestions. Downloads are excluded from
  Export/Delete All Data. This differs from the user's requested finer categories;
  record that gap rather than pretending the menu already implements it.
- A button-visibility preference is distinct from its engine prerequisite. Output
  visibility should follow its setting; the AI button also requires enabled AI
  and an installed usable model. Test persisted, preview and extension states.
- Language Priority is ordered. Supported suggestion paths use bounded boosts;
  order does not create Japanese predictions, reorder every decoder or force
  Qwen speech auto-detection into a ranked-language recognizer.
- Chinese/Cantonese preferences can recommend Heretic 0.8B, 2B or 9B based on memory.
  Selection and download remain explicit. 9B MAX-MTP is about 5.72 GB on disk and
  requires the current 12 GB physical / 8.4 GB available-memory policy. File size
  alone does not establish feasibility. Current inference is CPU; MTP acceleration
  and actual refusal behavior have not been verified.

## Blank-board investigation: preserve uncertainty

The reported problem recurs beyond first launch. Earlier screenshots have a top
resize handle, top-right Delete, and a 123/Emoji bottom row, which differ from
AltBoard's source layout. That supports an alternative-keyboard interpretation,
but the user could not confirm the selected keyboard. Do not dismiss the report
or assert a crash, memory termination, handwriting mode or swipe-trail cause.

Build 63 (`8c1d6b2`) is the pre-Globe comparison baseline. Build 65's source
(`166e820`) introduced the mandatory native Globe; build 75 (`cfbba6b`) introduced
letter-row fading during cursor tracking. Current main already removes that
fading and retains a bounded host. Another reset is not a demonstrated root fix.

The next decisive observations are the active keyboard name during failure,
whether explicitly selecting AltBoard restores it, and whether matching extension
crash/termination evidence exists. App/keyboard diagnostic build stamps must match;
a stored keyboard probe is historical evidence, not proof of the active keyboard.
Record host app, build, focus/gesture sequence and result without collecting typed
messages or secrets. Phone testing remains pending.

## Baseline verification and delivery

Build 120 completed compilation, packaging, entitlements, dictionary and exact-SHA
IPA checks. A downloaded copy passed `scripts/verify-ipa-bundle.py`; SHA-256:
`52143ac783e5df18f27ca0a2a2a3cde378c32269e42372720419adc802556984`.
20 focused Python keyboard/settings checks and three Swift checks (language order,
host geometry, model memory/prompt contracts) passed locally. These results apply
to the baseline app source; additional document-check results belong in delivery
metadata. No physical iPhone or live-model behavior was verified.

Do not rebuild or replace the user's test IPA for documentation alone. For a later
authorized build, use the single main IPA workflow. Keep source/build identity
explicit and deliver a machine-generated patch with new files and actual checks.
