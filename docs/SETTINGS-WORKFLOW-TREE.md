# AltBoard-Canto: current app and Settings menu

Generated from `APP-STRUCTURE.json`; edit the JSON and run
`python3 scripts/check-app-structure.py --write`.

Last installed diagnostic baseline: `7b7aa5c5041805783358fbfeb8a38b09a2922ec4` · build 124.
Live main source may include newer changes; this menu is not device verification.

Conditions and initial expansion state appear in parentheses. Descriptions
of dynamic lists describe repeated rows, not extra navigation destinations.

- History
  - Saved voice notes: playback, copy, correction/learning and delete
  - Try your keyboard here (system-selected keyboard; not forced to AltBoard)
- Meetings
  - Search meetings
  - Start a new meeting / Stop and save meeting
  - Recording information and 15-minute audio parts
  - Saved meeting
    - Playback
    - Rename
    - Transcript & Files
    - Delete (confirmation)
  - Transcript & Files
    - Name and notes / Save Name & Notes
    - Combined Transcript / Copy Transcript / Share
    - Saved Audio Parts
- Settings
  - Action Required (incomplete setup or low storage; rows depend on the condition)
    - Complete Setup
    - Low storage warning
  - Purchase section (APPSTORE configuration only)
  - Speech & AI
    - Language Priority
      - Preferred Languages: numbered, draggable ordering
      - Any language (empty preference)
      - Unsupported speech-model language warning
    - Active Session
    - Speech Model
      - Speech Models: filtered catalog, selected/download states
      - Advanced: Change Qwen model source
    - Text Model
      - Text Models: language filter, recommendation, selected/download states
      - Model update notice / Switch back / Remove
    - Dictation (initially collapsed)
      - Auto-Stop
      - Live Dictation
      - Output (initially collapsed)
        - Transcript Cleanup
        - Output Language
        - Tone
        - Language Code (custom output language; invalid code warning when needed)
      - Enable Meeting Recording
      - Cantonese Recognition Corrections
        - Edit speech-recognition correction rules
    - AI Actions (initially collapsed)
      - Enabled (disabled without usable downloaded text model)
      - Formatting (initially collapsed)
        - Writing Style
        - Snippets
        - Auto-Copy to Clipboard
      - Prompts (AI enabled and usable model installed)
        - Standard Prompts
        - Custom Prompts / Add Custom Prompt
      - Auto Action (AI enabled and usable model installed; applies to dictation)
      - Long Press Action (AI enabled and usable model installed)
  - Keyboard
    - Keyboard Type (Microphone Only / Symbols / Alphabet)
    - Microphone Layout (Microphone Only; Default / Compact)
    - Key Order (Alphabet; QWERTY (English) / QWERTZ / German (Ä Ö Ü ß))
    - Customization (initially collapsed)
      - Auto-capitalization
      - Double-Space Period
      - Haptic Feedback
      - Extra Globe Key (temporarily disabled; saved preference retained)
      - Settings Key
      - Output Key
      - AI Key (disabled when AI Actions is off; runtime toolbar additionally needs a usable text model)
    - Interactive keyboard preview (visible inline; selected layout)
  - App
    - History & Storage (initially collapsed)
      - Voice Notes
        - Export
        - Delete (confirmation)
      - Meetings
        - Export
        - Delete (confirmation)
      - Corrections & Suggestions
        - Export
        - Delete (confirmation)
      - Keep Voice Notes
      - Export All Data
      - Delete All Data (confirmation)
      - Clear Model Cache
    - App Language
      - Select app interface language
    - Setup & Permissions
      - Conditional setup checklist: microphone, keyboard, Full Access and speech model
    - Diagnostics
      - Permissions and Signing (app/keyboard build stamps and historical probe)
      - Offline Models
      - Audio and Device
      - Keyboard Touch Diagnostics
        - Show Key Touch Areas
        - Swipe & Touch Counters, Learning and Reset
          - Aggregate touch/swipe counters and learning/reset controls
      - Live Dictation
      - Functional Tests
        - Refresh all diagnostics
        - Test microphone without saving audio
        - Test ASR and AI cleanup / Stop and transcribe
      - Last Execution Steps
        - Refresh last execution steps
      - Export
        - Cantonese Learning & JSON Export
          - Aggregate Cantonese learning and vocabulary JSON export
        - Copy complete diagnostics
      - Development Traces (non-APPSTORE builds; initially collapsed)
        - Keyboard lifecycle / Feature milestones counts
        - Share Development Diagnostics JSON
        - Copy Development Diagnostics JSON
        - Refresh Diagnostic Counts
        - Clear Development Traces (confirmation)
    - Help
      - Report a problem: GitHub / email
    - Version
    - Altboard-Canto · Source on GitHub

## Ownership and known differences

- Active Session has one Settings-home owner; Dictation does not repeat the toggle.
- Customization is one collapsed group between conditional Key Order/Microphone Layout and the visible Preview. Haptics is a toggle.
- History & Storage is initially collapsed under App; current three categories combine corrections/suggestions and exclude downloaded models. See AB-DOC-003.
- Language order influences supported paths; it does not implement every language or decoder. Qwen speech uses auto-detection.
- Existing download, recommended model and actively selected model are separate. No file replacement or refusal behavior is implied.
- Diagnostics has additional technical controls outside Customization. No cleanup or deletion is authorized by documenting them.
- This map records current source rather than proposed menu changes. Update owners and conditions after bounded source review; regenerate Markdown.
- Temporary user-requested experiment suppresses Altboard Globe including required in-extension visibility; it cannot suppress iOS-owned controls outside the extension.
- Swipe drawing UIView mounts only after the active trail has more than one point; this is not a confirmed ink-pad fix.
- Dictation owns Output (Transcript Cleanup, Output Language, Tone, custom Language Code). AI Actions owns Formatting (Writing Style, Snippets, Auto-Copy). These are separate inline groups.
- History, Meetings and Settings change using the native tabs only; the custom horizontal page gesture was removed because it conflicted with scrolling and navigation.
- Build #124 is the last confirmed installed diagnostic baseline; subsequent source repairs require a new build and physical iPhone acceptance.
- Source owners and anchor checks are structural contracts; existing reference SHAs are historical, never a reason to rewrite current working code.

Consult `KNOWN-ISSUES.json` for evidence and pending acceptance checks.
