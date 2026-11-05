# Settings and input navigation

Source-owned architecture for Settings and input. Read current code when this map differs from the implementation.

## Main tabs

- **History** — saved voice notes and temporary keyboard test field. The X clears text first; with an empty field, it closes the keyboard.
- **Meetings** — local meeting recording, search, playback and editing.
- **Settings** — Speech & AI, Keyboard and App. Speech/Text models are Settings destinations, not a duplicate tab.

## Settings

### Speech & AI

1. **Language Priority** — numbered drag-to-reorder languages; empty means automatic language choice.
2. **Active Session** — the only active recording-session toggle, on Settings home.
3. **Speech Model** — speech-model manager.
4. **Text Model** — offline text-model manager.
5. **Dictation** — collapsed inline: Auto-Stop, Live Dictation, Enable Meeting Recording, Cantonese Recognition Corrections.
6. **Output** — transcript cleanup, output language, tone and text-output settings.
7. **AI Actions** — collapsed inline: Enabled, then Prompts, Auto Action and Long Press Action when a usable text model is selected. No duplicate model link.

### Keyboard

1. **Keyboard Type** — Microphone Only, Symbols, Alphabet.
2. **Microphone Layout** — only for Microphone Only: Default / Compact.
3. **Key Order** — only for Alphabet: QWERTY / QWERTZ / German.
4. **Customization** — collapsed inline: auto-capitalization, double-space period, one haptic toggle, optional Globe, Settings, Output and AI buttons.
5. Interactive keyboard preview directly below Customization, with no redundant "Preview" label.

There is no visible keyboard-height slider, haptic strength control, haptic test page, or additional keyboard-button submenu. Retain compatibility keys where needed without exposing duplicate controls.

### App

1. **History & Storage** — collapsed inline: local storage categories, export/delete, voice-note retention, all-data export/delete and compiled-cache clearing. Preserve confirmation and active-recording protection.
2. **App Language** — independent interface language.
3. **Setup & Permissions**
4. **Diagnostics**
5. **Help**
6. **Version** and source link.

## Source and state ownership

| Area | Source | State owner |
| --- | --- | --- |
| Navigation and collapses | `Sayboard/Views/SettingsView.swift` | Local presentation state |
| Keyboard layout, customization, preview | `KeyboardSettingsView.swift`, `KeyboardCustomizationView.swift` | App Group / `SharedSettings` |
| Dictation controls | `SettingsNavigationViews.swift` | Speech service / App Group |
| AI action controls | `LLMSettingsView.swift` | `SharedSettings` / `LLMDownloadService` |
| Ordered language selection | `SpeechLanguagesSettingsView.swift`, `LanguagePickerView.swift` | `SharedSettings.preferredSpokenLanguages` |
| History test X | `HistoryListView.swift` | Temporary, unsaved text |
| Extension layout and host text | `SayboardKeyboard/KeyboardViewController.swift`, `Views/Layouts/AlphabeticKeyboardLayout.swift` | UIKit document proxy |
| Native keyboard list | `SayboardKeyboard/Views/NativeInputModeSwitchKey.swift` | iOS input mode picker |

## Invariants

- One visible owner per decision; don't duplicate controls or persistent state when inlining a submenu.
- Keep the keyboard extension's UIKit touch owner and SwiftUI drawing/accessibility separate. Swipe trails are visual feedback, not a separate input mode.
- The iOS Chinese handwriting keyboard is a system input mode. Altboard's five-key Chinese stroke grid is not a freehand drawing canvas.
- Keep the host `UIHostingController` across ordinary focus changes; validate geometry and fallback paths before changing lifecycle ownership.
- `main` uses the existing `.github/workflows/build-unsigned-ipa.yml`; a successful build is not physical-device validation.
