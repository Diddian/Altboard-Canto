# Altboard-Canto: Settings and Workflow Tree

Source reviewed: fix/haptic-core-canto-ime-20261102 at c6673851b63b.
Repair branch: chore/settings-audit-tree-20261102.
This is a navigation proposal, NOT a claim that the proposed hierarchy is implemented.

## 1. Current app workflow (what the code does)

Altboard-Canto
|
+-- History tab
|   +-- Saved transcriptions and audio
|   +-- Play, review, and manage records
|   +-- Input field: test the installed keyboard
|   +-- Setup banner, when something is missing
|   +-- AI offer, when eligible
|
+-- Models tab
|   +-- Speech Recognition
|   |   +-- Select and download an offline speech model
|   |   +-- Filter models by language
|   |   +-- Set language preferences for a model
|   |   +-- Advanced Qwen model source
|   +-- Text Processing
|       +-- Download and manage an offline text model
|
+-- Settings tab
    +-- Setup warning (only when needed)
    +-- Purchase option (App Store builds only)
    +-- Dictation
    |   +-- Active Session
    |   +-- Auto-Stop
    |   +-- Active Session Info
    +-- History
    |   +-- Keep History
    |   +-- Clear All History
    +-- Storage
    |   +-- Clear Model Cache
    +-- Text
    |   +-- Writing Style
    |   +-- AI Text Processing
    |   +-- Snippets
    |   +-- Auto-Copy to Clipboard
    +-- Speech & Languages
    |   +-- Voice Output & Translation
    |       +-- Languages I Speak
    |       +-- Clean Up Transcription
    |       +-- Output Language
    |       +-- Dictation Tone
    |       +-- Speech Model shortcut
    |       +-- Text Model shortcut
    |       +-- Cantonese Word Corrections
    +-- Keyboard
    |   +-- Keyboard Type: Microphone Only / Symbols / Alphabet
    |   +-- Alphabet: QWERTZ / QWERTY
    |   +-- Alphabet: Auto-Capitalize
    |   +-- Alphabet: Cantonese scheme (only with Cantonese enabled)
    |   +-- Haptic Feedback, Driver, Strength, Tests
    |   +-- Keyboard Height and Interactive Preview
    |   +-- Double-Space Period
    +-- General
    |   +-- App Language
    +-- Troubleshooting
    |   +-- Diagnostics
    |   +-- Setup (when setup is already complete)
    +-- Report a Problem
    |   +-- GitHub Issue (currently points to upstream Altboard)
    |   +-- Support Email (currently points to upstream Altboard)
    +-- About
        +-- App Version

## 2. Suggested Settings structure

Keep the existing three main tabs. Do not turn Models into a Settings subpage.
Keep Keyboard mostly as it is. Group settings by what the user wants to do.

Settings
|
+-- Keyboard
|   +-- Keyboard Type
|   |   +-- Microphone Only
|   |   +-- Symbols
|   |   +-- Alphabet
|   +-- Alphabet Options (only when Alphabet is selected)
|   |   +-- QWERTZ / QWERTY
|   |   +-- Auto-Capitalize Sentences
|   |   +-- Cantonese Romanization (only when Cantonese is preferred)
|   |       +-- Jyutping
|   |       +-- Yale
|   |       +-- Yuetyam
|   +-- Keyboard Height
|   |   +-- Height Slider
|   |   +-- Interactive Keyboard Preview
|   |   +-- Reset to Recommended Height
|   +-- Haptic Feedback
|   |   +-- On / Off
|   |   +-- Strength
|   |   +-- Test Haptic
|   |   +-- Advanced Haptic Tests (link to Diagnostics)
|   +-- Typing Shortcuts
|       +-- Double-Space Period
|
+-- Dictation
|   +-- Active Session
|   +-- Auto-Stop
|   +-- Active Session Info
|
+-- Speech & Languages
|   +-- Languages I Speak
|   |   +-- Choose Cantonese, English, German, or other supported languages
|   |   +-- Cantonese choice also enables Alphabet Chinese suggestions
|   +-- Voice Output & Translation
|       +-- Clean Up Transcription with Offline AI
|       +-- Output Language
|       +-- Dictation Tone
|       +-- Cantonese Word Corrections
|       +-- Speech Model (shortcut to Models tab)
|       +-- Text Model (shortcut to Models tab)
|
+-- Text & AI
|   +-- Writing Style (text formatting)
|   +-- AI Text Processing
|   |   +-- Enable / Disable
|   |   +-- Prompts and Custom Prompts
|   |   +-- Auto Action
|   |   +-- Long Press Action
|   +-- Snippets
|   +-- Auto-Copy to Clipboard
|
+-- History & Storage
|   +-- Keep History
|   +-- Clear All History
|   +-- Clear Compiled Model Cache
|
+-- Help
|   +-- Setup and Permissions
|   +-- Diagnostics
|   |   +-- Device and Permissions
|   |   +-- Keyboard Full Access and App Group
|   |   +-- Haptic Tests and Events
|   |   +-- Microphone and Speech Tests
|   |   +-- Execution Logs
|   |   +-- Copy Diagnostic Report
|   +-- Report a Problem
|       +-- GitHub
|       +-- Email
|
+-- General
|   +-- App Language
|
+-- About
    +-- Version
    +-- Source Code and Licenses (possible future addition)

## 3. Speech processing workflow

Voice Dictation
+-- Keyboard microphone button
+-- Audio session and microphone capture
+-- Offline speech recognition
+-- Check allowed language or unexpected script
+-- Apply saved Cantonese corrections
+-- Optional offline AI cleanup, translation, and dictation tone
+-- Format final text and expand snippets
+-- Apply final Cantonese corrections where relevant
+-- Send text through App Group bridge to the host input field
+-- Save history and audio using the retention policy

Alphabet Typing
+-- Insert Latin letters directly into the host input field
+-- If Cantonese is preferred, look up offline Chinese candidates
+-- Offer the original Latin text and suitable English corrections
+-- If a Chinese candidate is selected, replace only the verified suffix
+-- Space keeps Latin and starts a new word
+-- Delete a recognized final romanized syllable when safe
+-- Otherwise use ordinary character deletion

Haptic Feedback
+-- Read one shared enabled/driver/strength preference
+-- Try Core Haptics
+-- Fall back to original SwiftUI sensory feedback if engine setup fails
+-- Keep UIKit as a comparison driver
+-- Save private-data-free attempt and error details in Diagnostics

## 4. Implementation order (proposal only)

1. Keep the small repairs already committed on the audit branch.
2. Move advanced haptic engine comparisons out of the everyday Keyboard page.
3. Put "Languages I Speak" one level above Voice Output, but retain ONE shared preference.
4. Let the main Models tab remain the only full model-management screen.
5. Share one set of keyboard geometry and colors across runtime and previews.
6. Share one microphone/ASR test engine between Setup and Diagnostics.
7. Move History and compiled model cache controls under History & Storage.
8. Verify navigation, Voice Output, keyboard preferences, onboarding, and SideStore persistence on device.

## 5. Naming rules

- "App Language" changes the app interface only.
- "Languages I Speak" controls speech recognition preferences and Cantonese typing suggestions.
- "Cantonese Romanization" controls candidate lookup, not a keyboard language switch.
- "Writing Style" formats text. "Dictation Tone" edits spoken transcription with AI.
- "AI Text Processing" controls keyboard AI actions and prompts.
- "Voice Output & Translation" controls the spoken-text pipeline.
- "Clear Compiled Model Cache" does not mean deleting downloaded models.
- Keep warnings and advanced troubleshooting outside everyday settings where possible.
