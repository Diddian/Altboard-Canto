# Altboard interface guide

Observed baseline: build 123, commit `d2fb55443e710ab492231073c9620de715f5eac9`,
5 November 2026. This is a native SwiftUI/UIKit iOS app and keyboard extension,
not a PWA. The filename follows the workspace contract.

## Evidence and boundaries

Reviewed owners: `Sayboard/Views/MainTabView.swift`, `SettingsView.swift`,
`KeyboardSettingsView.swift`, `VoiceOutputSettingsView.swift`,
`TextOutputSection.swift`, `LLMSettingsView.swift`,
`SayboardKeyboard/Views/Layouts/KeyboardChrome.swift`,
`AlphabeticKeyboardLayout.swift`, `Shared/KeyboardPalette.swift`,
`KeyboardLayoutGeometry.swift`, and `project.yml`.
The supplied 5 November screen recording shows native dark keyboard surfaces,
Altboard's letter layout, and a separate-looking ink pad. The pad's trigger and
ownership remain unresolved. A screenshot or successful build cannot prove them.

The following preservation rules derive from the existing code. Requirements for
new interactions are design decisions for this task, not claims of prior behaviour.

## Preserve the existing system

- Keep History / Meetings / Settings, their order, native tab controls,
  NavigationStack destinations, setup banners and deep links.
- Use native Form, Section, DisclosureGroup, Label, Picker and Toggle controls.
  Put an SF Symbol beside top-level settings groups, consistent with nearby rows.
  Keep secondary controls collapsed. Give each setting one maintained route.
- Preserve semantic system text styles, primary/secondary colours and native
  light/dark appearance. Keep bundled tab assets. Do not introduce a theme.
- Use `KeyboardPalette` for real keys and previews. Its dark backdrop is RGB
  33/33/33; key fill is 67/67/67. Preserve dynamic light-mode colours.
- Reuse `KeyboardLayoutGeometry` and `KeyboardChromeMetrics`; do not copy their
  measurements into another geometry policy. Current content heights are 277 pt
  for full typing, 260 pt for microphone default and 150 pt for compact microphone.
  Current key height is 45 pt and corner radius is scaled from 8.5 pt.
- Keep extension typing available without microphone permission, Full Access,
  an installed model or writable shared storage. Keep model inference in the app.

## Interaction and motion requirements

- Page swipes supplement the existing tabs. Preserve vertical scrolling,
  row actions, text editing, child navigation and the system edge-back gesture.
  Do not wrap past the first or last page. Do not require swiping for accessibility.
- Keep key feedback immediate. A swipe trail is a passive overlay over mounted
  letter keys, created only during a swipe and cleared at end/cancel/reappearance.
  It must never own touches or become an independent input mode.
- The temporary Globe experiment must affect the real keyboard and its preview.
  Preserve the stored preference for later restoration. It does not control an
  iOS-owned Globe outside the extension. Do not claim it fixes the ink pad.
- Preserve native disclosure/navigation motion. Honour Reduce Motion for added
  transitions. Avoid animations or delayed keyboard mounting in hot input paths.
- Explain actual behaviour: Writing Style also formats ordinary dictation;
  Snippets performs local phrase expansion; Auto-Copy affects the clipboard.
  Grouping these under AI Actions must not gate local features on an AI model.

## Accessibility and performance

- Keep text labels with symbols, meaningful accessibility names, native focus
  and control semantics, scalable app typography and usable enlarged text.
- Keep gesture shortcuts optional. Preserve accessible tab activation and
  keyboard text input. Avoid gesture interception over text fields or sliders.
- Observe frequent swipe points only in the trail component. Do not remount
  the whole keyboard per frame or rebuild a hosting controller per appearance.
- Reuse bounded diagnostics; never record typed messages, raw touch paths,
  audio or credentials. Empty traces do not prove that a feature never ran.

## Verification and acceptance

Run focused keyboard/settings contracts and parse changed Swift files. Compile
the iOS targets when Xcode and dependencies are available; report missing tools.
Inspect changed routes and previews, and review the patch against its exact base.
Keep build, source checks and phone checks separate.

Phone acceptance still required: repeated keyboard focus across WhatsApp, Notes
and Altboard; keys before/during/after swipes; cancellation and app switching;
Globe absence in all three layouts and previews; page swipes both ways at root;
vertical scrolling, row actions and child back navigation; icon alignment;
Output access with AI on/off and no model; light/dark appearance, larger text,
VoiceOver and Reduce Motion. Use the reported iPhone plus a smaller supported
screen when available. Record the tested build and actual outcomes.

No source check establishes that the recurring ink-pad issue is resolved.
