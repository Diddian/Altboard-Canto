import json
from pathlib import Path
import plistlib
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]


class StorageUsageContractTests(unittest.TestCase):
    def test_storage_events_only_record_lifecycle_metadata(self):
        service = (ROOT / "Sayboard/Services/StorageUsageService.swift").read_text()
        calls = re.findall(r"FeatureDiagnostics\.record\((.*?)\)", service, re.S)
        self.assertTrue(calls)
        events = set()
        allowed_arguments = {"operationID", "durationMs", "failureReason"}
        for call in calls:
            event = re.match(r"\.storage,\s*\.(\w+)", call)
            self.assertIsNotNone(event, call)
            events.add(event.group(1))
            arguments = set(re.findall(r"\b(\w+)\s*:", call))
            self.assertLessEqual(arguments, allowed_arguments)
            self.assertNotRegex(call, r"snapshot|inventory|capacity|\.path|\.bytes|\.name")
        self.assertLessEqual({"started", "completed", "failed", "cancelled", "fallback", "unavailable", "slow"}, events)

    def test_inventory_is_read_only_and_does_not_sample_contents(self):
        for path in ("StorageUsageInventory.swift", "StorageUsageService.swift"):
            source = (ROOT / "Sayboard/Services" / path).read_text()
            self.assertNotRegex(source, r"Data\(contentsOf:|String\(contentsOf:|JSONDecoder|PropertyListDecoder")
            self.assertNotRegex(source, r"removeItem|createDirectory|\.write\(|moveItem|copyItem|UserDefaults")

    def test_scan_worker_receives_view_cancellation(self):
        service = (ROOT / "Sayboard/Services/StorageUsageService.swift").read_text()
        view = (ROOT / "Sayboard/Views/DataAndStorageSettingsView.swift").read_text()
        self.assertIn("Task.detached(priority: .utility)", service)
        self.assertRegex(service, r"withTaskCancellationHandler[\s\S]+onCancel:\s*\{\s*worker\.cancel\(\)")
        self.assertIn(".task(id: self.storageRefreshID)", view)
        self.assertIn("try Task.checkCancellation()", view)
        self.assertIn("if let device = self.storage?.device", view)
        self.assertIn("Some files could not be measured. This total is incomplete.", view)

    def test_capacity_display_has_required_reason(self):
        with (ROOT / "Sayboard/PrivacyInfo.xcprivacy").open("rb") as source:
            manifest = plistlib.load(source)
        disk = next(item for item in manifest["NSPrivacyAccessedAPITypes"]
                    if item["NSPrivacyAccessedAPIType"] == "NSPrivacyAccessedAPICategoryDiskSpace")
        self.assertIn("85F4.1", disk["NSPrivacyAccessedAPITypeReasons"])
        self.assertIn("E174.1", disk["NSPrivacyAccessedAPITypeReasons"])

    def test_storage_strings_and_placeholders_are_complete(self):
        catalog = json.loads((ROOT / "Sayboard/Storage.xcstrings").read_text())
        source = (ROOT / "Sayboard/Services/StorageUsageInventory.swift").read_text()
        titles = re.findall(r'case \.\w+: "([^"]+)"', source)
        self.assertTrue(titles)
        self.assertTrue(set(titles).issubset(catalog["strings"]))
        for key, entry in catalog["strings"].items():
            count = len(re.findall(r"%(?:\d+\$)?@", key))
            for language in ("en", "de", "zh-Hant"):
                value = entry["localizations"][language]["stringUnit"]["value"]
                self.assertTrue(value.strip(), (key, language))
                self.assertEqual(count, len(re.findall(r"%(?:\d+\$)?@", value)), (key, language))


if __name__ == "__main__":
    unittest.main()
