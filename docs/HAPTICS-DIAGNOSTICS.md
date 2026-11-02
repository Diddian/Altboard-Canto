# Haptic diagnosis: iOS 27.2 / SideStore

## Grounded device observation
- Full Access = Yes and keyboard App Group = Yes.
- Core Haptics from the *containing app* produces real vibration.
- `UIImpactFeedbackGenerator` and `UISelectionFeedbackGenerator` were invoked in the app but did not cause felt vibration.
- The old diagnostic trace has only `app heavy` records. Keyboard extension calls have not been proven by it.

## Why this implementation changed
Original Altboard uses SwiftUI `.sensoryFeedback(.selection, trigger:)` from `KeyButton` and `SpaceBarKey`; the fork substituted UIKit generators, which are silent on the reported device. This branch makes **Core Haptics** the default (confirmed to vibrate in containing app), with a per-process engine reused between keys. If the extension cannot create/start Core Haptics, it falls back to the upstream SwiftUI `.sensoryFeedback` path. **UIKit** stays as an explicitly selectable comparison.

The public Core Haptics API returns an error when engine setup or playback fails. A successful API call does *not* prove a physical pulse. The app and extension have separate processes, so Core Haptics success in the app cannot prove it works in the extension.

References:
- https://github.com/Altboard/Altboard
- https://developer.apple.com/documentation/corehaptics
- https://developer.apple.com/documentation/uikit/uifeedbackgenerator
- https://jyutping.app/en/faq/

## Diagnostic sequence
1. Leave Settings > Keyboard > Haptic engine set to Core Haptics, tap **Test haptic** and preview letter keys. Confirm physical response.
2. Open History test input, switch to Altboard and type 10 letters. Do **not** clear the trace first unless you want a fresh experiment.
3. Return to Settings > Diagnostics and tap Refresh haptic trace. Look for `extension core`, `extension core->sensory` or `extension swiftui`; `app` alone is not evidence the extension attempted feedback.
4. Try `SwiftUI (original Altboard)` from Keyboard Settings and repeat to test the fallback independently.
5. If extension feedback remains silent, compare the user's system keyboard haptics, iOS vibration setting, SideStore entitlements and extension logs. Avoid private vibration/audio system sound IDs.

Trace stores only attempt count, driver, process origin, Full Access and error category. No typed characters, host bundle IDs, transcript or clipboard content.

On Core Haptics setup failure, trace includes the NSError domain and integer code, never user input. Distinguish `operationNotPermitted`, `notSupported` and server interruption before assuming Full Access is the cause.
