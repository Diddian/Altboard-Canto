
import Foundation

enum DictationOutcome: String, Sendable {
  case noSpeech

  case engineFailed

  case processingFailed

  case activationFailed

  case unexpectedLanguage
}
