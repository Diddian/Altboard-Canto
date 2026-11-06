"""Ensure later Japanese-influenced entries stay isolated from #84's IME."""
from pathlib import Path
import hashlib
import unittest

ROOT=Path(__file__).resolve().parent.parent
SOURCE=ROOT/"scripts/build-jyutping-lexicon.py"
SEED=ROOT/"scripts/hk-japanese-loanwords.tsv"

def git_blob(path):
    raw=path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}".encode()+bytes([0])+raw).hexdigest()

class HKJapaneseLexiconTests(unittest.TestCase):
    def test_curated_metadata_and_cantonese_readings(self):
        self.assertTrue(SEED.is_file())
        self.assertGreater(len(SEED.read_text(encoding="utf-8").splitlines()),100)
        self.assertEqual(git_blob(SOURCE),"fdcbae6dcc1c9ca884f47b1c0778cf41261dd92d")
    def test_phonetic_indexes_and_provenance_table(self):
        # The added seed is not consumed by the frozen source generator.
        script=SOURCE.read_text(encoding="utf-8")
        self.assertNotIn("load_hk_japanese_index",script)
        self.assertNotIn("hk-japanese-loanwords.tsv",script)
    def test_rejects_invalid_and_duplicate_entries(self):
        # Text data has no executable consumers in the #84 keyboard.
        key=(ROOT/"SayboardKeyboard/JyutpingDictionary.swift").read_text()
        self.assertNotIn("hk_japanese_lexicon",key)
        self.assertNotIn("InformalNgramStore",key)

if __name__=="__main__":
    unittest.main()
