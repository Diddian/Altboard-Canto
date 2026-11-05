#!/usr/bin/env python3
"""Check reviewed source fingerprints and render the documented menu; no Swift parsing."""
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
MAP = ROOT / "docs/APP-STRUCTURE.json"
MENU = ROOT / "docs/SETTINGS-WORKFLOW-TREE.md"


def render(data):
    lines = [
        "# AltBoard-Canto: current app and Settings menu", "",
        "Generated from `APP-STRUCTURE.json`; edit the JSON and run",
        "`python3 scripts/check-app-structure.py --write`.", "",
        f"App source baseline: `{data['baseline']['commit']}` · build {data['baseline']['build']}.",
        "This records source structure, not physical-device verification.", "",
        "Conditions and initial expansion state appear in parentheses. Descriptions",
        "of dynamic lists describe repeated rows, not extra navigation destinations.", "",
    ]

    def walk(nodes, depth=0):
        for node in nodes:
            conditions = []
            if node.get("condition"):
                conditions.append(node["condition"])
            if "initially_expanded" in node:
                conditions.append("initially expanded" if node["initially_expanded"] else "initially collapsed")
            suffix = " (" + "; ".join(conditions) + ")" if conditions else ""
            lines.append("  " * depth + "- " + node["label"] + suffix)
            walk(node.get("children", []), depth + 1)

    walk(data["navigation"])
    lines += ["", "## Ownership and known differences", ""]
    lines += ["- " + note for note in data["consistency_notes"]]
    lines += ["", "Consult `KNOWN-ISSUES.json` for evidence and pending acceptance checks.", ""]
    return "\n".join(lines)


def validate(data):
    errors = []
    owners = data["source_owners"]
    for relative, expected in owners.items():
        path = ROOT / relative
        if not path.is_file():
            errors.append(f"Missing owner: {relative}")
        elif hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            errors.append(f"Stale owner: {relative}; review its map entries before updating its hash")
    ids = set()

    def walk(nodes):
        for node in nodes:
            if node["id"] in ids:
                errors.append(f"Duplicate node ID: {node['id']}")
            ids.add(node["id"])
            owner = node["owner"]
            if owner not in owners:
                errors.append(f"Untracked owner for {node['id']}: {owner}")
            anchor = node.get("source_anchor")
            if anchor and (ROOT / owner).is_file():
                if anchor not in (ROOT / owner).read_text():
                    errors.append(f"Missing anchor for {node['id']}: {anchor}")
            walk(node.get("children", []))

    walk(data["navigation"])
    for feature in data["feature_entry_points"]:
        for owner in feature["owners"]:
            if owner not in owners:
                errors.append(f"Untracked feature owner: {owner}")
    return errors, len(ids)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    args = parser.parse_args()
    data = json.loads(MAP.read_text())
    errors, count = validate(data)
    expected = render(data)
    if args.check and (not MENU.is_file() or MENU.read_text() != expected):
        errors.append("Menu drift: regenerate SETTINGS-WORKFLOW-TREE.md from the reviewed JSON")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    if args.write:
        MENU.write_text(expected)
    print(f"Verified {count} unique menu nodes and {len(data['source_owners'])} reviewed source fingerprints")
    return 0


if __name__ == "__main__":
    sys.exit(main())
