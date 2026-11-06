# Keyboard loading compatibility conflicts

Base: build 136 (`be3bcb6ba992d5c72e0bfe217f2f0dcf3706e44e`). Loading reference: build 84 (`fc5b1714e161ba59075b41212c959f4a076931aa`).

This development experiment replaces input-view creation, hosting mount timing and height application with the build 84 path. Build 136 UI, input features, native switch selector, microphone state machine and diagnostics remain. Conflict repairs are deferred until device results are available.

| Area | Conflict or evidence | Disposition |
| --- | --- | --- |
| Initial settings and basic-typing fallback | Build 107 refreshed settings, input traits and Full Access before mounting. The restored build 84 order mounts first, so the first frame may use stale state. | Retain the reference order for this experiment; investigate after device testing. |
| Height synchronization | Build 107 updated hosting height independently when UIKit had not created the input-height constraint. The build 84 early return can skip that update, or skip it when only hosting height differs. | Defer repair; compare initial appearance, mode changes and permission fallback. |
| Custom geometry host | Build 119 introduced KeyboardInputView, early mounting and a geometry-gated root; build 130 kept the root mounted across zero-size transitions. | Remove that wrapper and use direct bottom-anchored hosting. Existing lifecycle and UIKit render probes remain. Wrapper-specific rootReady/rootWaiting events no longer originate from the removed wrapper. |
| Gesture and focus recovery | Builds 105–107 and later added appearance revisions, cursor cancellation, touch-row reset and field-change recovery. | Retain build 136 recovery logic; these are not a wholesale rollback of the keyboard controller. |
| System input-mode registration | Build 85 changed IsASCIICapable from false to true and PrimaryLanguage from mis to yue-Hant-HK. Native handleInputModeList wiring is unchanged between the reference and base. | Retain build 136 registration. Its relationship to system selection failures is unproven. |
| Document identity and async insertion | Build 133 added optional document-identifier guards used by cursor movement, live dictation and AI results. | Retain guards and associated diagnostics. |
| Reported system keyboard crash | The supplied November 6 crash report identifies Apple's kbd process aborting in TITypingSessionAligned. | Separate evidence from an extension rendering failure; causal connection to this loading change is unproven. |

The build 85–135 additions retained from build 136 include Cantonese phrase and alias expansion, adaptive romanization, multilingual predictions and learning, microphone hold/release handling, model selection, ordered language settings, custom Emoji behavior, and development exports. No layout, settings or feature redesign is part of this experiment.
