#!/usr/bin/env python3
"""Read-only verification of the actual unsigned iPhone IPA.

Supports legacy Altboard IPAs with an emoji_catalog.tsv and the new unified
build that intentionally uses the iOS system Emoji keyboard instead.
"""
import argparse
import json
import pathlib
import plistlib
import re
import sqlite3
import tempfile
import zipfile


class BundleValidationError(ValueError):
    pass


APP = "Payload/Sayboard.app/"
KEYBOARD = APP + "PlugIns/SayboardKeyboard.appex/"
EMOJI = KEYBOARD + "emoji_catalog.tsv"
REQUIRED = (
    APP + "Info.plist",
    KEYBOARD + "Info.plist",
    KEYBOARD + "jyutping.sqlite3",
)
INDEXES = {"idx_entries_plain", "idx_entries_compact", "idx_entries_yale", "idx_entries_sidney"}


def inspect_ipa(
    path: pathlib.Path,
    *,
    expected_sha: str | None = None,
    expect_native_emoji: bool = False,
    min_entries: int = 10_000,
    min_emoji: int = 3_000,
) -> dict:
    try:
        with zipfile.ZipFile(path) as ipa:
            names = set(ipa.namelist())
            absent = set(REQUIRED) - names
            if absent:
                raise BundleValidationError("Missing IPA payload files: " + ", ".join(sorted(absent)))
            if any(ipa.getinfo(n).file_size == 0 for n in REQUIRED):
                raise BundleValidationError("Empty required app/keyboard resource")
            if ipa.getinfo(KEYBOARD + "jyutping.sqlite3").file_size > 90_000_000:
                raise BundleValidationError("Offline SQLite resource unexpectedly large")
            if expect_native_emoji and EMOJI in names:
                raise BundleValidationError("Obsolete custom Emoji catalog present in native-Emoji IPA")
            app = plistlib.loads(ipa.read(APP + "Info.plist"))
            extension = plistlib.loads(ipa.read(KEYBOARD + "Info.plist"))
            sha = app.get("AltboardBuildSHA")
            if not isinstance(sha, str) or not re.fullmatch("[0-9a-f]{40}", sha):
                raise BundleValidationError("App build SHA missing or malformed")
            if sha != extension.get("AltboardBuildSHA"):
                raise BundleValidationError("App/keyboard build SHA mismatch")
            if expected_sha is not None and sha != expected_sha:
                raise BundleValidationError("Built SHA differs from requested Actions commit")
            app_id = app.get("CFBundleIdentifier")
            keyboard_id = extension.get("CFBundleIdentifier")
            if not isinstance(app_id, str) or keyboard_id != app_id + ".keyboard":
                raise BundleValidationError("Keyboard extension bundle identifier is invalid")
            with tempfile.TemporaryDirectory(prefix="altboard-ipa-qa-") as tmp:
                db_path = pathlib.Path(tmp) / "jyutping.sqlite3"
                db_path.write_bytes(ipa.read(KEYBOARD + "jyutping.sqlite3"))
                db = sqlite3.connect("file:" + str(db_path) + "?mode=ro", uri=True)
                try:
                    if db.execute("PRAGMA quick_check").fetchone() != ("ok",):
                        raise BundleValidationError("SQLite quick_check failed")
                    count = db.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
                    indexes = {row[0] for row in db.execute(
                        "SELECT name FROM sqlite_master WHERE type='index'"
                    )}
                    if count < min_entries or not INDEXES.issubset(indexes):
                        raise BundleValidationError("Offline dictionary too small or required index missing")
                finally:
                    db.close()

            emoji_count = 0
            if EMOJI in names:
                rows = ipa.read(EMOJI).decode("utf-8").splitlines()
                if not rows or rows[0] not in (
                    "group\tname\temoji", "group\tname\temoji\tversion"
                ):
                    raise BundleValidationError("Malformed legacy Emoji catalogue")
                width = len(rows[0].split("\t"))
                symbols = set()
                for line in rows[1:]:
                    cols = line.split("\t")
                    if len(cols) != width or not all(cols) or cols[2] in symbols:
                        raise BundleValidationError("Invalid or duplicate Emoji row")
                    symbols.add(cols[2])
                emoji_count = len(symbols)
                if emoji_count < min_emoji:
                    raise BundleValidationError("Legacy Emoji catalogue unexpectedly small")
            corrupt = ipa.testzip()
            if corrupt:
                raise BundleValidationError("Corrupted IPA member: " + corrupt)
            return {
                "sha": sha,
                "app_bundle": app_id,
                "keyboard_bundle": keyboard_id,
                "sqlite_entries": count,
                "sqlite_indexes": len(indexes),
                "emoji_mode": "system" if EMOJI not in names else "legacy_extension",
                "emoji_entries": emoji_count,
                "ipa_bytes": path.stat().st_size,
            }
    except (OSError, zipfile.BadZipFile, sqlite3.DatabaseError, plistlib.InvalidFileException) as error:
        raise BundleValidationError(str(error)) from error


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=pathlib.Path)
    parser.add_argument("--expected-sha", help="Exact 40-character GitHub commit SHA")
    parser.add_argument("--expect-native-emoji", action="store_true")
    args = parser.parse_args()
    try:
        result = inspect_ipa(
            args.ipa, expected_sha=args.expected_sha, expect_native_emoji=args.expect_native_emoji
        )
    except BundleValidationError as error:
        parser.exit(1, "IPA INVALID: " + str(error) + "\n")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
