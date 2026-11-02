#!/usr/bin/env python3
"""Create the keyboard's offline, searchable RGI emoji catalogue (Unicode Emoji 18.0).
Source: https://www.unicode.org/Public/18.0.0/emoji/emoji-test.txt
Unicode data license: https://www.unicode.org/license.txt
The extension never downloads emoji data or sends emoji searches to a server.
"""
import argparse
import pathlib
import re
import urllib.request

SOURCE = "https://www.unicode.org/Public/18.0.0/emoji/emoji-test.txt"
VERSION = "# Version: 18.0"
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
    if args.input:
        source = pathlib.Path(args.input).read_text(encoding="utf-8")
    else:
        req = urllib.request.Request(SOURCE, headers={"User-Agent": "Altboard-Canto-EmojiBuilder"})
        with urllib.request.urlopen(req, timeout=60) as response:
            source = response.read().decode("utf-8")
        if VERSION not in source:
            raise ValueError("Unexpected Unicode Emoji version")
    entries = parse_catalog(source)
    if not args.input and len(entries) < 3000:
        raise ValueError(f"Incomplete emoji catalogue: {len(entries)} entries")
    output = pathlib.Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("group\tname\temoji\n" + "\n".join("\t".join(row) for row in entries) + "\n", encoding="utf-8")
    print(f"Emoji catalogue: {len(entries)} fully-qualified RGI entries")


if __name__ == "__main__":
    main()
