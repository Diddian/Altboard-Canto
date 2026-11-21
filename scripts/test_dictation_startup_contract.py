"""Guard cancellation ownership at the UI/controller boundary."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parent.parent


class DictationStartupContractTests(unittest.TestCase):
    def test_views_and_readiness_probes_cannot_end_capture_requests(self):
        mic = (ROOT / "SayboardKeyboard/Views/Layouts/MicAnimatedButton.swift").read_text()
        probe = (ROOT / "SayboardKeyboard/PingValidator.swift").read_text()
        self.assertNotIn("dictationOutcome = .activationFailed", mic)
        self.assertNotIn("keyboardState.isStartingRecording = false", probe)
        self.assertNotIn("keyboardState.isRecording = false", probe)

    def test_failed_start_cancels_but_confirmed_frames_are_finalized(self):
        owner = (ROOT / "SayboardKeyboard/KeyboardViewController+Startup.swift").read_text()
        expired = owner.split("case .expired:", 1)[1].split("case .waiting:", 1)[0]
        recorded = owner.split("case .finishCapturedSpeech:", 1)[1].split("case .expired:", 1)[0]
        self.assertLess(expired.index("self.cancelDictationViaDarwin()"),
                        expired.index(".activationFailed"))
        self.assertIn("self.stopDictationViaDarwin()", recorded)
        self.assertNotIn("self.cancelDictationViaDarwin()", recorded)

    def test_view_reentry_resumes_the_persisted_deadline(self):
        controller = (ROOT / "SayboardKeyboard/KeyboardViewController.swift").read_text()
        hidden = controller.split("override func viewWillDisappear(", 1)[1].split(
            "override func didReceiveMemoryWarning", 1)[0]
        visible = controller.split("override func viewDidAppear(", 1)[1].split(
            "override func viewDidDisappear", 1)[0]
        self.assertIn("self.pauseDictationStartup()", hidden)
        self.assertNotIn("self.finishDictationStartup(", hidden)
        self.assertIn("self.resumeDictationStartupIfNeeded()", visible)


if __name__ == "__main__":
    unittest.main()
