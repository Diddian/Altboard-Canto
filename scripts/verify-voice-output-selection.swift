import Foundation

@main
enum VerifyVoiceOutputSelection {
  private struct Selection: Equatable {
    let target: String
    let register: String
  }

  static func main() {
    let spoken = Selection(target: "original", register: "faithful")
    let german = Selection(target: "german", register: "faithful")
    let english = Selection(target: "english", register: "faithful")
    let formalGerman = Selection(target: "german", register: "formal")
    precondition(VoiceOutputSelectionPolicy.decide(
      processed: german, current: german, attempt: 1) == .deliver)
    precondition(VoiceOutputSelectionPolicy.decide(
      processed: spoken, current: german, attempt: 1) == .retry)
    precondition(VoiceOutputSelectionPolicy.decide(
      processed: german, current: spoken, attempt: 1) == .retry)
    precondition(VoiceOutputSelectionPolicy.decide(
      processed: german, current: english, attempt: 2) == .retry)
    precondition(VoiceOutputSelectionPolicy.decide(
      processed: german, current: formalGerman, attempt: 2) == .retry)
    precondition(VoiceOutputSelectionPolicy.decide(
      processed: german, current: english, attempt: 3) == .reject)
    precondition(VoiceOutputSelectionPolicy.decide(
      processed: english, current: english, attempt: 3) == .deliver)
    print("Late voice output selection and stale-translation rejection passed")
  }
}
