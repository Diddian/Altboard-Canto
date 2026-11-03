"""Synthetic-package checks; the actual IPA is verified in the release job."""
import importlib.util
import pathlib
import plistlib
import sqlite3
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "ipa_validator", ROOT / "scripts" / "verify-ipa-bundle.py"
)
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)
SHA = "a" * 40


def fixture(directory, *, legacy=False, extension_sha=SHA, missing=None,
            merged_shapes=False, unicode_license=False):
    directory = pathlib.Path(directory)
    sqlite_file = directory / "jyutping.sqlite3"
    db = sqlite3.connect(sqlite_file)
    db.execute("CREATE TABLE entries(word TEXT)")
    for name in MOD.INDEXES:
        db.execute("CREATE INDEX " + name + " ON entries(word)")
    db.execute("INSERT INTO entries(word) VALUES ('佢')")
    db.commit()
    db.close()
    payload = {
        MOD.APP + "Info.plist": plistlib.dumps({
            "CFBundleIdentifier": "app.sayboard", "AltboardBuildSHA": SHA
        }),
        MOD.KEYBOARD + "Info.plist": plistlib.dumps({
            "CFBundleIdentifier": "app.sayboard.keyboard",
            "AltboardBuildSHA": extension_sha
        }),
        MOD.KEYBOARD + "jyutping.sqlite3": sqlite_file.read_bytes(),
    }
    if merged_shapes:
        shapes_file = directory / "chinese-shapes.sqlite3"
        shape_db = sqlite3.connect(shapes_file)
        shape_db.execute(
            "CREATE TABLE entries(method TEXT, variant INTEGER, "
            "code TEXT, word TEXT, source TEXT)"
        )
        shape_db.executemany("INSERT INTO entries VALUES (?,?,?,?,?)", [
            ("stroke", 0, "m", "一", "stroke5"),
            ("stroke", 0, "m", "一", "rime-stroke"),
            ("quick", 3, "aa", "昌", "quick3"),
            ("quick", 5, "aa", "昌", "quick5"),
            ("cangjie", 3, "aa", "昌", "cangjie3"),
            ("cangjie", 5, "aa", "昌", "cangjie5"),
        ])
        shape_db.execute("CREATE TABLE stroke_prefix(prefix TEXT, word TEXT)")
        shape_db.execute("INSERT INTO stroke_prefix VALUES ('m','一')")
        shape_db.commit()
        shape_db.close()
        payload[MOD.SHAPES] = shapes_file.read_bytes()
        payload[MOD.MERGED_NOTICES[0]] = b"LGPL-3.0 terms"
        payload[MOD.MERGED_NOTICES[1]] = b"GPLv3 terms"
        payload[MOD.MERGED_NOTICES[2]] = b"Rime Stroke attribution"
    if unicode_license:
        payload[MOD.UNICODE_LICENSE] = b"UNICODE LICENSE V3 permission notice"
    if legacy:
        payload[MOD.EMOJI] = "group\tname\temoji\nSmileys\tgrin\t😀\n".encode()
    if missing:
        del payload[missing]
    archive = directory / "test.ipa"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in payload.items():
            z.writestr(name, data)
    return archive


class IPABundleTests(unittest.TestCase):
    def test_custom_emoji_requires_catalog_and_license(self):
        with tempfile.TemporaryDirectory() as tmp:
            missing = fixture(tmp)
            with self.assertRaisesRegex(MOD.BundleValidationError,
                                        "Emoji resources missing"):
                MOD.inspect_ipa(missing, expect_emoji_catalog=True)

        with tempfile.TemporaryDirectory() as tmp:
            ipa = fixture(tmp, legacy=True, unicode_license=True)
            result = MOD.inspect_ipa(
                ipa, expected_sha=SHA, expect_emoji_catalog=True,
                min_entries=1, min_emoji=1
            )
            self.assertEqual(result["emoji_mode"], "custom_extension")
            self.assertEqual(result["emoji_entries"], 1)

    def test_native_system_emoji_passes_without_custom_catalog(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = fixture(tmp)
            actual = MOD.inspect_ipa(
                ipa, expected_sha=SHA, expect_native_emoji=True, min_entries=1
            )
            self.assertEqual(actual["emoji_mode"], "system")
            self.assertEqual(actual["sqlite_entries"], 1)

    def test_merged_stroke_sources_and_notices_in_extension(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = fixture(tmp, merged_shapes=True)
            result = MOD.inspect_ipa(
                ipa, expected_sha=SHA, expect_merged_shapes=True,
                expect_native_emoji=True, min_entries=1,
                min_stroke_source_entries=1
            )
            self.assertEqual(result["stroke_sources"]["rime-stroke"], 1)
            self.assertEqual(result["stroke_sources"]["stroke5"], 1)

    def test_merged_stroke_requires_license(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = fixture(tmp, merged_shapes=True,
                          missing=MOD.MERGED_NOTICES[0])
            with self.assertRaisesRegex(MOD.BundleValidationError,
                                        "Missing merged stroke resources"):
                MOD.inspect_ipa(ipa, expect_merged_shapes=True)

    def test_legacy_catalog_remains_backward_compatible(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = fixture(tmp, legacy=True)
            actual = MOD.inspect_ipa(ipa, expected_sha=SHA, min_entries=1, min_emoji=1)
            self.assertEqual(actual["emoji_entries"], 1)
            self.assertEqual(actual["emoji_mode"], "legacy_extension")

    def test_native_build_rejects_obsolete_catalog(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = fixture(tmp, legacy=True)
            with self.assertRaisesRegex(MOD.BundleValidationError, "Obsolete"):
                MOD.inspect_ipa(ipa, expect_native_emoji=True)

    def test_missing_extension_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = fixture(tmp, missing=MOD.KEYBOARD + "Info.plist")
            with self.assertRaisesRegex(MOD.BundleValidationError, "Missing IPA"):
                MOD.inspect_ipa(ipa)

    def test_keyboard_stamp_mismatch_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = fixture(tmp, extension_sha="b" * 40)
            with self.assertRaisesRegex(MOD.BundleValidationError, "SHA mismatch"):
                MOD.inspect_ipa(ipa)

    def test_wrong_expected_sha_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            ipa = fixture(tmp)
            with self.assertRaisesRegex(MOD.BundleValidationError, "differs"):
                MOD.inspect_ipa(ipa, expected_sha="b" * 40, min_entries=1)


if __name__ == "__main__":
    unittest.main()
