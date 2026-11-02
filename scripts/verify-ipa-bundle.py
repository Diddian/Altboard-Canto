#!/usr/bin/env python3
"""Offline QA for an unsigned SideStore IPA; never modifies or signs the archive.

Checks: app/extension identity, matching AltboardBuildSHA, SQLite data/indexes
and emoji RGI catalog. Run after downloading the exact GitHub Actions artifact.
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
REQUIRED = (
    APP + "Info.plist",
    KEYBOARD + "Info.plist",
    KEYBOARD + "jyutping.sqlite3",
    KEYBOARD + "emoji_catalog.tsv",
)
REQUIRED_INDEXES = {"idx_entries_plain", "idx_entries_compact", "idx_entries_yale", "idx_entries_sidney"}


def inspect_ipa(path: pathlib.Path, *, expected_sha: str | None = None,
                min_entries: int = 10000, min_emoji: int = 3000) -> dict:
    """Return facts about the package or raise BundleValidationError."""
    try:
        with zipfile.ZipFile(path) as ipa:
            names = set(ipa.namelist())
            missing = [item for item in REQUIRED if item not in names]
            if missing:
                raise BundleValidationError("Missing IPA payload files: " + ", ".join(missing))
            for name in REQUIRED:
                if ipa.getinfo(name).file_size == 0:
                    raise BundleValidationError("Empty IPA payload file: " + name)
            if ipa.getinfo(KEYBOARD + "jyutping.sqlite3").file_size > 90_000_000:
                raise BundleValidationError("Unexpectedly large SQLite payload")
            if ipa.getinfo(KEYBOARD + "emoji_catalog.tsv").file_size > 20_000_000:
                raise BundleValidationError("Unexpectedly large emoji payload")
            app = plistlib.loads(ipa.read(APP + "Info.plist"))
            keyboard = plistlib.loads(ipa.read(KEYBOARD + "Info.plist"))
            app_sha = app.get("AltboardBuildSHA")
            extension_sha = keyboard.get("AltboardBuildSHA")
            if app_sha != extension_sha or not isinstance(app_sha, str):
                raise BundleValidationError("App/extension build SHA mismatch")
            if not re.fullmatch(r"[0-9a-f]{40}", app_sha):
                raise BundleValidationError("Missing or invalid stamped build SHA")
            if expected_sha is not None and app_sha != expected_sha:
                raise BundleValidationError("Build SHA differs from requested Actions commit")
            app_bundle = app.get("CFBundleIdentifier")
            extension_bundle = keyboard.get("CFBundleIdentifier")
            if not isinstance(app_bundle, str) or not isinstance(extension_bundle, str):
                raise BundleValidationError("Missing bundle identifiers")
            if extension_bundle != app_bundle + ".keyboard":
                raise BundleValidationError("Keyboard extension bundle identifier does not match app")

            with tempfile.TemporaryDirectory(prefix="altboard-ipa-qa-") as tmp:
                database = pathlib.Path(tmp) / "jyutping.sqlite3"
                database.write_bytes(ipa.read(KEYBOARD + "jyutping.sqlite3"))
                con = sqlite3.connect("file:" + str(database) + "?mode=ro", uri=True)
                try:
                    if con.execute("PRAGMA quick_check").fetchone() != ("ok",):
                        raise BundleValidationError("Offline SQLite quick_check failed")
                    entries = con.execute("SELECT COUNT(*) FROM entries").fetchone()[0]
                    indexes = {item[0] for item in con.execute(
                        "SELECT name FROM sqlite_master WHERE type='index'"
                    )}
                    if not REQUIRED_INDEXES.issubset(indexes):
                        raise BundleValidationError("Romanization indexes missing from offline SQLite")
                    if entries < min_entries:
                        raise BundleValidationError("Offline SQLite has too few entries: " + str(entries))
                finally:
                    con.close()
            raw = ipa.read(KEYBOARD + "emoji_catalog.tsv").decode("utf-8")
            rows = raw.splitlines()
            header = rows[0] if rows else ""
            # Earlier IPA assets use 3 columns; the new emoji-parity branch
            # stores an additional Unicode emoji introduction version.
            expected_columns = {
                "group\tname\temoji": 3,
                "group\tname\temoji\tversion": 4,
            }.get(header)
            if expected_columns is None:
                raise BundleValidationError("Malformed emoji catalog header")
            if len(rows) - 1 < min_emoji:
                raise BundleValidationError("Emoji catalog has too few entries")
            symbols = set()
            groups = set()
            for line in rows[1:]:
                fields = line.split("\t")
                if len(fields) != expected_columns or any(not field for field in fields):
                    raise BundleValidationError("Malformed emoji catalog row")
                if expected_columns == 4:
                    try:
                        if float(fields[3]) < 0 or float(fields[3]) > 99:
                            raise ValueError("out of range")
                    except ValueError as error:
                        raise BundleValidationError("Invalid emoji introduction version") from error
                groups.add(fields[0])
                if fields[2] in symbols:
                    raise BundleValidationError("Duplicate emoji sequence")
                symbols.add(fields[2])
            corrupted = ipa.testzip()
            if corrupted:
                raise BundleValidationError("Corrupt IPA ZIP member: " + corrupted)
            return {
                "sha": app_sha,
                "app_bundle": app_bundle,
                "keyboard_bundle": extension_bundle,
                "sqlite_entries": entries,
                "sqlite_index_count": len(indexes),
                "emoji_entries": len(rows) - 1,
                "emoji_groups": len(groups),
                "ipa_bytes": path.stat().st_size,
            }
    except (OSError, zipfile.BadZipFile, sqlite3.DatabaseError, plistlib.InvalidFileException) as error:
        raise BundleValidationError(str(error)) from error


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("ipa", type=pathlib.Path)
    parser.add_argument("--expected-sha", help="Full 40-character GitHub Actions head SHA")
    args = parser.parse_args()
    try:
        results = inspect_ipa(args.ipa, expected_sha=args.expected_sha)
    except BundleValidationError as error:
        parser.exit(1, "IPA INVALID: " + str(error) + "\n")
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
