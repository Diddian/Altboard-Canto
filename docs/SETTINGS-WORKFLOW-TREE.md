# Altboard-Canto: Settings and App Workflow

Implemented branch: feat/fixed-keyboard-settings-20261102
Base: chore/settings-audit-tree-20261102

This tree describes the settings screens in the new review build. It is
plain English; indentation means a child screen or control.

## Main navigation

Altboard-Canto
|
+-- History
|   +-- Saved transcriptions and recordings
|   +-- Playback, copy and delete
|   +-- Try Your Keyboard input (stays above the bottom navigation bar)
|
+-- Models
|   +-- Speech Recognition (offline ASR)
|   +-- Text Processing (offline LLM)
|
+-- Settings
    |
    +-- Keyboard
    |   +-- Layout
    |   |   +-- Keyboard Type
    |   |   |   +-- Microphone Only
    |   |   |   +-- Symbols
    |   |   |   +-- Alphabet
    |   |   +-- Microphone Layout (only in Microphone Only)
    |   |   |   +-- Default: large round microphone
    |   |   |   +-- Compact: microphone bar above Space
    |   |   +-- Alphabet Options (only in Alphabet)
    |   |       +-- Key Order: QWERTZ or QWERTY
    |   |       +-- Auto-Capitalize Sentences
    |   |       +-- Cantonese Romanization (only when Cantonese is preferred)
    |   |           +-- Jyutping
    |   |           +-- Yale
    |   |           +-- Yuetyam
    |   +-- Feedback
    |   |   +-- Haptic Feedback: On / Off
    |   |   +-- Haptic Strength
    |   |   +-- Test Haptic
    |   |   +-- Haptic Method
    |   |   +-- Advanced Haptic Diagnostics
    |   +-- Typing Shortcuts
    |   |   +-- Double-Space Period
    |   +-- Keyboard Preview
    |       +-- Tap keys to test haptics
    |
    +-- Dictation
    |   +-- Active Session
    |   +-- Auto-Stop
    |   +-- Active Session Info
    |
    +-- Speech & Languages
    |   +-- Languages I Speak
    |   |   +-- Preferred spoken languages
    |   |   +-- Cantonese also enables Alphabet Chinese candidates
    |   +-- Voice Output & Translation
    |   |   +-- Clean Up Transcription
    |   |   +-- Output Language
    |   |   +-- Dictation Tone
    |   |   +-- Speech Recognition Model shortcut
    |   |   +-- Offline Cleanup / Translation Model shortcut
    |   |   +-- Cantonese Word Corrections
    |   +-- Speech Recognition Model shortcut
    |
    +-- Text & AI
    |   +-- Writing Style (ordinary text formatting)
    |   +-- AI Text Processing
    |   |   +-- Enable / Disable
    |   |   +-- Prompts
    |   |   |   +-- Standard Prompts
    |   |   |   +-- Custom Prompts
    |   |   +-- Auto Action
    |   |   +-- Long Press Action
    |   +-- Snippets
    |   +-- Auto-Copy to Clipboard
    |
    +-- History & Storage
    |   +-- Keep History
    |   +-- Clear All History (confirmation required)
    |   +-- Clear Compiled Model Cache (confirmation required)
    |
    +-- Help
    |   +-- Setup & Permissions
    |   +-- Diagnostics
    |   |   +-- Permissions and Signing
    |   |   +-- Offline Models
    |   |   +-- Haptic Tests
    |   |   +-- Microphone and Speech Tests
    |   |   +-- Execution Logs
    |   |   +-- Copy Diagnostics
    |   +-- Report a Problem
    |       +-- GitHub Issue
    |       +-- Email
    |
    +-- General
    |   +-- App Language
    |
    +-- About
        +-- Version
        +-- Full Version (App Store builds only)

## Keyboard sizing rules

Keyboard
|
+-- Microphone Only
|   +-- Default: fixed 260 pt iPhone canvas, large round microphone
|   +-- Compact: fixed 150 pt iPhone canvas, wide mic above Space
|
+-- Symbols
|   +-- Fixed 312 pt iPhone canvas
|
+-- Alphabet
    +-- Fixed 312 pt iPhone canvas
    +-- Full toolbar inside the keyboard; no negative top offset
    +-- Fixed 45 pt letter keys and 11 pt row spacing

The previous 70%-110% keyboard-height setting has been removed from Settings.
Old height values stored on the device are ignored. This is not a value
migration: only Microphone Only has a new explicit Default/Compact preference.

## Voice and text workflow

Keyboard microphone
+-- Start recording
+-- Offline speech recognizer
+-- Check allowed languages
+-- Offline Cantonese corrections
+-- Optional offline AI cleanup or translation
+-- Format, apply snippets and final corrections
+-- Insert into host app
+-- Save history according to retention policy

Alphabet keyboard
+-- Send Latin keys directly to the host
+-- Show Cantonese candidates if Cantonese is preferred
+-- Keep raw English as a candidate
+-- Replace only the verified typed suffix when a Chinese candidate is chosen
+-- Space keeps Latin and starts a new word
+-- Backspace deletes the last complete Cantonese syllable when safe

## Change status

- Implemented in the review branch: fixed keyboard sizing, compact mic selection,
  Settings grouping, shared keyboard geometry, touch-down haptic triggers,
  and asynchronous haptic diagnostics.
- Not proven until real iPhone testing: perceived haptic latency, toolbar safe
  bounds in every host, and exact microphone feel.
- Not changed: the offline speech engine, model storage, AI inference, history
  retention policy, and direct IPA packaging.

## Dismissing the keyboard

Custom keyboard
+-- Start downward swipe in top 22 pt
+-- Follow touch with slide and fade
+-- Dismiss at 56 pt, or quick 28 pt flick
+-- Cancel / sideways drag: restore layout
+-- Keep key taps, suggestions and spacebar cursor control intact

History screen
+-- Tap outside keyboard test field: dismiss
+-- Drag History list: interactive dismissal
+-- Switch tabs: keyboard test loses focus

Other host apps
+-- Host app decides what background taps do
+-- Altboard top-edge swipe works through Apple's dismissKeyboard() API
