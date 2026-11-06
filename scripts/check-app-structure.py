#!/usr/bin/env python3
"""Verify live navigation owners without publishing a stale menu snapshot."""
import argparse
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
def main():
    p=argparse.ArgumentParser()
    p.add_argument("--check",action="store_true")
    args=p.parse_args()
    if not args.check:
        p.error("Use --check")
    cases={
      "Sayboard/Views/MainTabView.swift": ["case history","case meetings","case settings","MeetingRecordsView()"],
      "Sayboard/Views/SettingsView.swift": ["Section(\"Speech & AI\")",
           "Section(\"Recording\")", "Section(\"Keyboard\")", "Section(\"Data\")",
           "KeyboardSettingsView(", "DataAndStorageSettingsView()",
           "DictationSettingsView()", "LLMSettingsView()",
           "AppLanguageListView()", "DiagnosticsView()"],
      "Sayboard/Views/SettingsNavigationViews.swift": ["struct DictationSettingsView",
           "struct HelpSettingsView"],
      "Sayboard/Services/LocalUserDataStore.swift": ["static func export(",
           "static func delete("]
    }
    errors=[]
    for name,needles in cases.items():
        file=ROOT/name
        if not file.is_file():
            errors.append("Missing "+name)
            continue
        s=file.read_text(encoding="utf-8")
        for needle in needles:
            if needle not in s: errors.append(name+": missing "+needle)
    if errors:
        for e in errors: print(e)
        return 1
    print("Current app routes and data-operation owners verified")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
