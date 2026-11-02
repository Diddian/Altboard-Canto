# Altboard-Canto: Focused Code and Settings Audit

Baseline: fix/haptic-core-canto-ime-20261102, c6673851b63b.
Review: 2026-11-02.
Scope: Settings navigation, related workflows, keyboard previews, onboarding, App Group preferences, and build/release structure.

This is a targeted source review, not a full call-graph proof for every Swift symbol.
Do not delete migration or compatibility code just because newer iOS disables a feature.

## Applied as small repairs on chore/settings-audit-tree-20261102

- SettingsView.swift:
  - Read keyboard type from shared App Group @AppStorage instead of a one-time @State snapshot.
  - Keep the existing KeyboardSettingsView binding and stored raw values.
  - Move Clear Model Cache from About into Storage.
  - Move App Language out of About into General.
  - Show Setup under Troubleshooting when onboarding is complete.
  - Rename "Speech to Text and Translation" to "Speech & Languages".
  - Rename the destination row "Voice Output & Translation".
- VoiceOutputSettingsView.swift:
  - Rename its "Writing style" picker to "Dictation tone".
  - This is a label fix. It does not merge it with Text > Writing Style.
- OnboardingKeyboardTypeView.swift:
  - Stop describing Alphabet as English-only; it also supports Cantonese suggestions.
- OnboardingPracticeView.swift:
  - Replace the hidden Standard/Extended toggle with an explicit choice of all three keyboard types.
  - This prevents selecting Alphabet earlier and then silently being switched to Microphone Only.
- Remove the zero-byte OnboardingDebugMenu.swift placeholder.

These changes do not rename UserDefaults keys, reconfigure the offline speech models,
remove features, or change the runtime keyboard's key geometry.

## Confirmed overlapping implementations; not removed yet

- Three separate keyboard representations:
  - SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift is real input.
  - Sayboard/Views/KeyboardSettingsView.swift has an interactive height preview.
  - Sayboard/Views/Onboarding/KeyboardLayoutPreview.swift draws onboarding previews.
  - The previews have hard-coded spacing and control positions. Share a small metrics
    and palette model instead of pretending the three full views are interchangeable.
- Setup and Diagnostics both implement microphone and ASR test interactions:
  - Sayboard/Views/SetupView.swift
  - Sayboard/Views/DiagnosticsView.swift
  - Keep two destinations for user purpose, but reuse one test service and one report format.
- Multiple ways to reach model management:
  - ModelsView.swift is the main Models tab with Speech and Text segments.
  - LLMSettingsView.swift also defines LLMModelsScreen.
  - VoiceOutputSettingsView.swift links to both model screens.
  - Use one canonical model-management destination with shortcuts from Settings.
- Output and AI cross-links:
  - SettingsView.swift links to VoiceOutputSettingsView.
  - TextOutputSection.swift links to LLMSettingsView.
  - LLMSettingsView.swift links back to VoiceOutputSettingsView.
  - These links are not unused code, but make navigation harder to understand.

## Legacy and potentially dead code; verify before deletion

- Per-app writing styles:
  - WritingStyleListView.swift and AppSearchService.swift handle app-specific styles.
  - DefaultStylePickerView.swift still exposes archived per-app choices.
  - SharedSettings.canResolveHostApplication and OperatingSystem.isHostBundleIdBroken
    guard older or constrained iOS behavior.
  - This is compatibility/migration logic, not proven dead. Verify the minimum
    supported iOS and user data migration before removing it.
- MainTabView.swift installs TabBarTapInterceptor with an empty callback.
  - It is NOT dead: seven Settings tab taps toggle useCustomSpaceBar as a hidden
    side effect. Consider moving the control to a developer/debug page, with a
    clear name and normal accessibility semantics.
- MainTabView.swift uses .equatable() on SettingsView and ModelsView, each of
  which returns true for equality. This may be intentional for performance.
  - Check whether externally updated App Group settings cause the screen to
    refresh. Do not remove the optimization without an observable regression.
- SupportLinks.swift currently reports to Altboard/Altboard upstream and uses
  upstream support@altboard.app. The fork's GitHub Issues are currently disabled.
  - Do not silently redirect reports until this fork has a working support path.
  - Label the destination clearly if it is meant to remain upstream.

## Source-to-output workflow

- Main tab navigation: Sayboard/Views/MainTabView.swift
- Settings root: Sayboard/Views/SettingsView.swift
- Text settings: Sayboard/Views/TextOutputSection.swift
- Voice settings: Sayboard/Views/VoiceOutputSettingsView.swift
- AI settings: Sayboard/Views/LLMSettingsView.swift
- Keyboard settings: Sayboard/Views/KeyboardSettingsView.swift
- Canonical persistent preferences: Shared/SharedSettings.swift and Shared/Constants.swift
- Speech finalization: Sayboard/Services/SpeechRecognitionService+Transcription.swift
- Keyboard literal input and offline suggestions:
  SayboardKeyboard/Views/Layouts/AlphabeticKeyboardLayout.swift and
  SayboardKeyboard/JyutpingDictionary.swift
- Keyboard haptics: Shared/KeyboardHaptics.swift and
  Shared/KeyboardHapticTrace.swift
- Diagnostics: Sayboard/Views/DiagnosticsView.swift
- SideStore IPA build: .github/workflows/build-unsigned-ipa.yml

## Build and validation

- Baseline CI run 41371506646 passed on c6673851b63b.
- No new iPhone build has been run for this audit branch.
- Build workflow currently triggers on four named development branches only.
  This audit branch is not included, avoiding a costly unattended IPA rebuild.
- This audit has reviewed the Settings and related source, not all 429 tree
  entries as a complete semantic symbol-use scan.
- Before merging the code repairs, run the existing iOS build and verify:
  - Settings keyboard type updates after choosing a type elsewhere.
  - Storage cache clear remains confirmed and only clears compiled cache.
  - History retention and clear confirmation still work.
  - App Language selection persists.
  - The new onboarding type chooser preserves Alphabet.
  - Voice Output and AI settings remain accessible.
  - SideStore App Group and keyboard extension build match.

## Follow-up order

1. Build and test this small review branch once before merge.
2. Merge only when settings and onboarding tests pass.
3. Refactor preview geometry and microphone tests in separate changes.
4. Do not delete historical host-app style data until migration tests exist.
5. Implement the proposed navigation tree after agreeing on labels.
