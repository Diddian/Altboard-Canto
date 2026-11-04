#!/usr/bin/env python3
"""Create the keyboard's offline, searchable RGI emoji catalogue (Unicode Emoji 17.0).
Source: https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt
Unicode data license: https://www.unicode.org/license.txt
The extension never downloads emoji data or sends emoji searches to a server.
"""
import argparse
import pathlib
import re

SOURCE = "https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt"
# Pinned from unicode-org/unicodetools tag final-17.0-20250910.
# CI must not depend on Unicode.org being reachable at build time.
DATA_DIR = pathlib.Path(__file__).resolve().parent / "data"
VERSION = "# Version: 17.0"
EMOJI_NAME = re.compile(r"^E[0-9]+(?:\.[0-9]+)?\s+")


def parse_catalog(source: str) -> list[tuple[str, str, str]]:
    group = ""
    rows = []
    seen = set()
    for line in source.splitlines():
        if line.startswith("# group: "):
            group = line.removeprefix("# group: ").strip()
            continue
        if ";" not in line or "#" not in line or not group:
            continue
        codepoints, rest = line.split(";", 1)
        status, description = rest.split("#", 1)
        if status.strip() != "fully-qualified":
            continue
        emoji = "".join(chr(int(item, 16)) for item in codepoints.split())
        name = EMOJI_NAME.sub("", description.strip().split(" ", 1)[1] if " " in description.strip() else "")
        # Description format: "😀 E1.0 grinning face".
        if not name:
            desc = description.strip()
            pieces = desc.split(" ", 2)
            name = pieces[-1] if len(pieces) == 3 else "emoji"
        name = name.replace("\t", " ").replace("\n", " ")
        if emoji not in seen:
            rows.append((group, name, emoji))
            seen.add(emoji)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", help="Optional local emoji-test.txt fixture")
    parser.add_argument("--output", default="EmojiResources/emoji_catalog.tsv")
    args = parser.parse_args()
    source_path = pathlib.Path(args.input) if args.input else DATA_DIR / "emoji-test-17.0.txt"
    source = source_path.read_text(encoding="utf-8")
    if not args.input and VERSION not in source:
        raise ValueError("Unexpected Unicode Emoji version")
    entries = parse_catalog(source)
    if not args.input and len(entries) < 3000:
        raise ValueError(f"Incomplete emoji catalogue: {len(entries)} entries")
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("group\tname\temoji\n" + "\n".join("\t".join(row) for row in entries) + "\n", encoding="utf-8")
    if not args.input:
        license_text = (DATA_DIR / "UnicodeLicense.txt").read_text(encoding="utf-8")
        if "UNICODE LICENSE V3" not in license_text:
            raise ValueError("Unexpected Unicode permission notice")
        (output.parent / "UnicodeLicense.txt").write_text(
            license_text, encoding="utf-8"
        )
    print(f"Emoji catalogue: {len(entries)} fully-qualified RGI entries")


if __name__ == "__main__":
    main()
