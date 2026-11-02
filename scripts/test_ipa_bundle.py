"""Zero-network unsigned IPA integrity checks with a synthetic tiny archive."""
import importlib.util
import pathlib
import plistlib
import sqlite3
import tempfile
import unittest
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("ipa_checker", ROOT / "scripts" / "verify-ipa-bundle.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)
SHA = "a" * 40


class IPABundleTests(unittest.TestCase):
    def make_ipa(self, directory, *, extension_sha=SHA, omit=None, entries=1):
        source = pathlib.Path(directory) / "lexicon.db"
        db = sqlite3.connect(source)
        db.execute("CREATE TABLE entries(word TEXT)")
        for name in MOD.REQUIRED_INDEXES:
            db.execute("CREATE INDEX " + name + " ON entries(word)")
        db.executemany("INSERT INTO entries(word) VALUES (?)", [("佢",)] * entries)
        db.commit()
        db.close()
        target = pathlib.Path(directory) / "test.ipa"
        app = {"AltboardBuildSHA": SHA, "CFBundleIdentifier": "app.sayboard"}
        keyboard = {"AltboardBuildSHA": extension_sha, "CFBundleIdentifier": "app.sayboard.keyboard"}
        payload = {
            MOD.APP + "Info.plist": plistlib.dumps(app),
            MOD.KEYBOARD + "Info.plist": plistlib.dumps(keyboard),
            MOD.KEYBOARD + "jyutping.sqlite3": source.read_bytes(),
            MOD.KEYBOARD + "emoji_catalog.tsv": b"group\tname\temoji\nSmileys & Emotion\tgrinning face\t\xf0\x9f\x98\x80\n",
        }
        if omit:
            payload.pop(omit)
        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
            for name, data in payload.items():
                archive.writestr(name, data)
        return target

    def test_valid_and_sha_verified(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.make_ipa(tmp)
            result = MOD.inspect_ipa(path, expected_sha=SHA, min_entries=1, min_emoji=1)
            self.assertEqual(result["sqlite_entries"], 1)
            self.assertEqual(result["emoji_entries"], 1)
            self.assertEqual(result["sha"], SHA)

    def test_extended_unicode_catalog_is_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.make_ipa(tmp)
            target = pathlib.Path(tmp) / "extended.ipa"
            with zipfile.ZipFile(path) as source, zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as result:
                for name in source.namelist():
                    raw = source.read(name)
                    if name == MOD.KEYBOARD + "emoji_catalog.tsv":
                        raw = "group\tname\temoji\tversion\nSmileys & Emotion\tgrinning face\t😀\t1.0\n".encode()
                    result.writestr(name, raw)
            parsed = MOD.inspect_ipa(target, min_entries=1, min_emoji=1)
            self.assertEqual(parsed["emoji_entries"], 1)

    def test_missing_keyboard_catalog_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.make_ipa(tmp, omit=MOD.KEYBOARD + "emoji_catalog.tsv")
            with self.assertRaisesRegex(MOD.BundleValidationError, "Missing IPA payload"):
                MOD.inspect_ipa(path, min_entries=1, min_emoji=1)

    def test_app_extension_stamp_mismatch_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.make_ipa(tmp, extension_sha="b" * 40)
            with self.assertRaisesRegex(MOD.BundleValidationError, "SHA mismatch"):
                MOD.inspect_ipa(path, min_entries=1, min_emoji=1)

    def test_wrong_expected_commit_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.make_ipa(tmp)
            with self.assertRaisesRegex(MOD.BundleValidationError, "differs"):
                MOD.inspect_ipa(path, expected_sha="b" * 40, min_entries=1, min_emoji=1)

    def test_too_few_emoji_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.make_ipa(tmp)
            with self.assertRaisesRegex(MOD.BundleValidationError, "too few"):
                MOD.inspect_ipa(path, min_entries=1, min_emoji=3000)

    def test_too_few_dictionary_entries_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self.make_ipa(tmp)
            with self.assertRaisesRegex(MOD.BundleValidationError, "too few"):
                MOD.inspect_ipa(path, min_entries=10000, min_emoji=1)


if __name__ == "__main__":
    unittest.main()
