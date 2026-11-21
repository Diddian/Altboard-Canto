"""Exercise the IPA naming and publication commands without network access."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
WORKFLOW = (ROOT / ".github/workflows/build-unsigned-ipa.yml").read_text()
SHA = "a" * 40


def step(name):
    match = re.search(
        r"^      - name: " + re.escape(name) + r"\n(.*?)(?=^      - name: |\Z)",
        WORKFLOW, re.M | re.S,
    )
    if not match:
        raise AssertionError(f"Missing workflow step: {name}")
    return match.group(1)


def command(name):
    body = step(name).split("        run: |\n", 1)[1]
    lines = []
    for line in body.splitlines():
        if line.startswith("          "):
            lines.append(line[10:])
        elif line.strip():
            break
    return "\n".join(lines) + "\n"


class DevelopmentDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "dist").mkdir()
        (self.root / "bin").mkdir()
        self.payload = b"synthetic IPA payload"
        (self.root / "dist/Altboard-Canto-SideStore.ipa").write_bytes(self.payload)
        gh = self.root / "bin/gh"
        gh.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, pathlib, sys\n"
            "with pathlib.Path(os.environ['MOCK_GH_LOG']).open('a') as output:\n"
            "    output.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "sys.exit(int(os.environ.get('MOCK_GH_EXIT', '0')))\n"
        )
        gh.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": str(self.root / "bin") + os.pathsep + os.environ["PATH"],
            "GITHUB_RUN_NUMBER": "260",
            "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_RUN_ID": "12345",
            "GITHUB_SHA": SHA,
            "GITHUB_REPOSITORY": "Diddian/Altboard-Canto",
            "GITHUB_OUTPUT": str(self.root / "output"),
            "GITHUB_STEP_SUMMARY": str(self.root / "summary"),
            "RUNNER_TEMP": str(self.root),
            "MOCK_GH_LOG": str(self.root / "gh.jsonl"),
            "ARTIFACT_URL": "https://github.com/Diddian/Altboard-Canto/actions/runs/12345/artifacts/9",
        }

    def run_step(self, name, *, succeeds=True):
        result = subprocess.run(
            ["bash", "-c", command(name)], cwd=self.root, env=self.env,
            text=True, capture_output=True,
        )
        if succeeds:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0)
        return result

    def package(self):
        self.run_step("Name the development IPA")
        outputs = dict(line.split("=", 1) for line in
                       (self.root / "output").read_text().splitlines())
        self.env["IPA_NAME"] = outputs["ipa_name"]
        return outputs

    def test_naming_keeps_previous_attempt_and_source(self):
        first = self.package()
        self.env["GITHUB_RUN_ATTEMPT"] = "2"
        second = self.package()
        self.assertNotEqual(first["ipa_path"], second["ipa_path"])
        self.assertIn("260", first["ipa_name"])
        for path in (first["ipa_path"], second["ipa_path"],
                     "dist/Altboard-Canto-SideStore.ipa"):
            self.assertEqual((self.root / path).read_bytes(), self.payload)

    def test_missing_ipa_does_not_create_download_output(self):
        (self.root / "dist/Altboard-Canto-SideStore.ipa").unlink()
        self.run_step("Name the development IPA", succeeds=False)
        self.assertFalse((self.root / "output").exists())

    def test_single_upload_is_available_for_every_successful_build(self):
        self.assertEqual(WORKFLOW.count("uses: actions/upload-artifact@"), 1)
        upload = step("Upload IPA to this Actions run")
        self.assertNotIn("        if:", upload)
        self.assertIn("archive: false", upload)
        self.assertIn("path: ${{ steps.package.outputs.ipa_path }}", upload)
        self.assertLess(WORKFLOW.index("Verify the single physical-iPhone IPA artifact"),
                        WORKFLOW.index("Upload IPA to this Actions run"))

    def test_artifact_download_survives_release_failure(self):
        self.package()
        self.run_step("Link the Actions download")
        before = (self.root / "summary").read_text()
        self.assertIn(self.env["ARTIFACT_URL"], before)
        self.env["MOCK_GH_EXIT"] = "1"
        self.run_step("Publish direct development IPA download", succeeds=False)
        self.assertEqual((self.root / "summary").read_text(), before)

    def test_release_has_exact_source_and_preserves_previous_builds(self):
        outputs = self.package()
        self.run_step("Publish direct development IPA download")
        calls = [json.loads(line) for line in
                 (self.root / "gh.jsonl").read_text().splitlines()]
        self.assertEqual(len(calls), 1)
        args = calls[0]
        self.assertEqual(args[:4], ["release", "create", "altboard-canto-dev-260-1",
                                   outputs["ipa_path"]])
        self.assertEqual(args[args.index("--target") + 1], SHA)
        self.assertIn("--prerelease", args)
        self.assertIn("--latest=false", args)
        self.assertNotIn("--clobber", WORKFLOW)
        self.assertNotIn('"force=true"', WORKFLOW)
        self.assertNotIn("altboard-canto-main-dev", WORKFLOW)
        notes = (self.root / "development-release.md").read_text()
        self.assertIn(SHA, notes)
        self.assertIn(hashlib.sha256(self.payload).hexdigest(), notes)
        summary = (self.root / "summary").read_text()
        expected = ("https://github.com/Diddian/Altboard-Canto/releases/download/"
                    "altboard-canto-dev-260-1/" + outputs["ipa_name"])
        self.assertIn(expected, summary)

    def test_retry_uses_a_new_release_tag(self):
        self.env["GITHUB_RUN_ATTEMPT"] = "2"
        self.package()
        self.run_step("Publish direct development IPA download")
        args = json.loads((self.root / "gh.jsonl").read_text())
        self.assertEqual(args[2], "altboard-canto-dev-260-2")

    def test_missing_artifact_url_is_not_advertised(self):
        self.env["ARTIFACT_URL"] = ""
        self.run_step("Link the Actions download", succeeds=False)
        self.assertFalse((self.root / "summary").exists())


if __name__ == "__main__":
    unittest.main()
