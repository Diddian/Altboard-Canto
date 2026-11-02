# Haptic troubleshooting (iOS custom keyboard)

## What the app actually measures

Altboard-Canto calls public UIKit `UISelectionFeedbackGenerator` and `UIImpactFeedbackGenerator` APIs. Requests from the keyboard extension and main Settings app are recorded into an App Group `UserDefaults` ring buffer (max 40 events). The log stores **no characters, content, host application names, or transcription**. The system does not return a "vibration succeeded" result; event counts only establish attempted API calls.

References:
- Apple: https://developer.apple.com/documentation/uikit/uifeedbackgenerator
- Apple's custom keyboard limitations: https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard
- Open-source keyboard reference: https://github.com/JoeManto/Haptic-Feedback-Keyboard (legacy iOS <13; its README documents Taptic Engine restrictions in extensions).
- SwiftKey/Gboard provide user-facing haptic controls, but their private implementation is not a public API to copy.

## Reproduce

1. On an actual iPhone (not simulator), open Altboard > Settings > Keyboard and tap Test haptic and its interactive preview.
2. Open Settings > Diagnostics > Haptic Diagnostics. Tap Selection, Soft, Light, Medium, Heavy and Core Haptics (app) tests.
3. In History, focus the new keyboard-testing field, switch to Altboard, type 10 letters. Return to Diagnostics, refresh haptic trace and copy the diagnostics.
4. Compare **main-app trace** against **keyboard extension trace**. If app tests vibrate but the extension does not, the problem is not letter-button layout or keyboard setting; extension-context haptic delivery is the likely cause.
5. Verify iOS Settings > Accessibility > Touch > Vibration. Compare with Apple's system keyboard feedback Settings > Sounds & Haptics > Keyboard Feedback.
6. If trace shows no keyboard attempts, test whether the extension has App Group access and Full Access, whether your SideStore install preserved entitlements and whether the keyboard view actually receives touch events.
7. If requests are logged but still silent, UIKit does not report physical output. Do not claim that changing intensity fixes iOS extension restrictions. Do not use private Taptic Engine APIs or undocumented system sounds.

## Acceptance

- Each keyboard press sends exactly one public UIKit request (subject to long-press behavior).
- Preview and the main-app diagnostic use the same shared haptic settings as the extension.
- Main app reports hardware Core Haptics support and errors; trace includes timestamp, request count, request type, app/extension origin, and Full Access status.
- Normal typing stays responsive; haptic traces never store typed input.
