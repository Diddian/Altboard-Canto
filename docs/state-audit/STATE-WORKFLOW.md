# Altboard-Canto runtime state workflow

Source baseline: Build 193 (`2157207`, failed before Xcode). This audit inferred 44 state families, 29 relationships, and 16 risks. Inspected later `main` `cdccc29f5751531b10b9308f47b1f27369054fc3` produced successful Build 199, but older risks and physical iPhone operation require fresh verification.

Canonical machine model: [`state-machines.json`](./state-machines.json). Existing [`APP-STRUCTURE.json`](../APP-STRUCTURE.json) and [`SETTINGS-WORKFLOW-TREE.md`](../SETTINGS-WORKFLOW-TREE.md) are navigation documents, not runtime reachability proofs.

## Input, output and shared resource map

```mermaid
flowchart LR
 subgraph Keyboard["Keyboard extension"]
  Globe["UIKit Globe key"] --> Picker["Native iOS keyboard menu"]
  Touch["UIKit touch owner"] --> IME["Yue / English / Deutsch / swipe"]
  Touch --> Haptics["Haptic settings + per-process engine"]
  Mic["Mic / AI request"] --> Capture
  Final["Final result + requestID + documentEpoch"] --> Match{"Same document?"}
  Match -->|yes| HostField["Host input field"]
  Match -->|no| Recover["Recover without auto-insertion"]
  IME --> HostField
 end
 subgraph Host["Containing app"]
  Conversation["Conversation / Meeting"] --> Capture["Capture lease"]
  Capture --> Audio["AVAudioSession owner"]
  Conversation --> ASR["ASR decode/load lease"]
  Conversation --> TextModel["Text-model lease"]
  ASR --> Final
  TextModel --> Final
 end
 Haptics -. "one gesture, one pulse" .-> Touch
 ASR -. "cancel + join before unload" .-> TextModel
```

## Build 193 diagrams (historical source-derived states)

### Current resource relationships

Classification: `current_source_model`; proposed edges are not implemented simply because they are drawn.

```mermaid
flowchart TD
  D["Keyboard dictation"] --> C["Shared capture gate"]
  M["Meetings"] --> C
  V["Conversation"] --> C
  D --> A["ASR engines"]
  M --> A
  V --> A
  M --> L["Text coordinator"]
  V --> L
  D --> L
  L -. "Unload lacks shared lease" .-> A
  C --> S["Audio session"]
  D -. "Cancel can end foreign session" .-> S
  P["Meeting playback"] -. "Sets playback category" .-> S
```

### Current dictation phases

Classification: `current_source_model`; proposed edges are not implemented simply because they are drawn.

```mermaid
stateDiagram-v2
  [*] --> Requested
  Requested --> Recording: capture acknowledged
  Requested --> Failed: activation failure
  Recording --> Draining: stop
  Draining --> Loading: recognizer needed
  Loading --> Transcribing
  Transcribing --> ProcessingOutput
  ProcessingOutput --> ProcessingOutput: bounded target change retry
  ProcessingOutput --> Delivering: current target matches
  ProcessingOutput --> Failed: output failure
  Delivering --> Idle: save and stopped notification
  Recording --> Cancelled: cancel
  Cancelled --> Idle
  Failed --> Idle
```

### Current delivery gap and proposed contract

Classification: `current_and_proposed`; proposed edges are not implemented simply because they are drawn.

```mermaid
flowchart TD
  subgraph Current["Current final-only path"]
    A["Request in field A"] --> F["Plain transcription file"]
    F --> B["Current proxy may be field B"]
  end
  subgraph Proposed["Proposed delivery contract"]
    R["Request and destination epoch"] --> O["Pending result envelope"]
    O --> G{"Request and destination match?"}
    G -->|Yes| I["Insert once and acknowledge"]
    G -->|No or unknown| K["Retain for explicit review"]
  end
```

### Download cancellation crosses an install boundary

Classification: `current_and_proposed`; proposed edges are not implemented simply because they are drawn.

```mermaid
sequenceDiagram
  participant A as Installer A
  participant R as Download registry
  participant U as User retry
  A->>R: Check variant key exists
  A->>A: Verify and extract
  U->>R: Cancel A, enqueue B under same key
  A->>R: Complete by key
  Note over A,R: Current completion can remove B
  Note over A,R: Proposed commit checks exact generation
```

### Conversation crash-recovery window

Classification: `current_and_proposed`; proposed edges are not implemented simply because they are drawn.

```mermaid
flowchart TD
  J["Proposed capture-intent journal"] -.-> A["Create CAF"]
  A --> B["Record, stop and join workers"]
  B --> C["Append turn and persist manifest"]
  A --> X["Process exits before manifest"]
  B --> X
  X --> R["Restore reads turns.json only"]
  R --> O["Orphan audio lacks visible turn"]
```

### Proposed domain ownership

Classification: `recommendation`; proposed edges are not implemented simply because they are drawn.

```mermaid
flowchart TD
  UI["UI projections and commands"] --> C["Identified intents"]
  C --> D["Domain state owners"]
  D --> L["Resource leases"]
  D --> S["Versioned runtime snapshot"]
  S --> UI
  D --> O["Result and consume acknowledgement"]
  O --> UI
  D --> T["Correlated metadata diagnostics"]
```

## Maintenance contract

Each domain has one writer. Request/owner/generation bounds cancellation and async completions. Model inference and decoding use shared leases. Insertions require matching field identity; unknown destinations retain results for manual recovery. Globe remains native iOS; haptics use per-process generation-aware lifecycle. Diagnostics omit sensitive user content.

The seven E01–E07 reviews are submachine candidates, not seven newly verified state families. Check latest main first and update the JSON only with evidence. The Settings tree is generated from APP-STRUCTURE.json, not hand-edited.
