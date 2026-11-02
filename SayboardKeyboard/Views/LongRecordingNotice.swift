import SwiftUI

/// An advisory during longer recordings; never blocks the microphone.
struct LongRecordingNotice: View {
  let startedAt: TimeInterval
  @AppStorage(SharedKey.longRecordingHintSeen,
              store: UserDefaults(suiteName: AppGroup.identifier))
  private var hasSeenHint = false
  @State private var showFirstHint = false

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { timeline in
      let seconds = startedAt > 0
        ? max(0, Int(timeline.date.timeIntervalSinceReferenceDate - startedAt)) : 0
      if seconds >= 40 {
        HStack(spacing: 3.kbScaled) {
          Image(systemName: "exclamationmark.triangle")
          if self.showFirstHint {
            Text("Long audio takes longer to transcribe").lineLimit(2)
          } else {
            Text("\(seconds)s").monospacedDigit()
          }
        }
        .font(.system(size: 9.kbScaled, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(maxWidth: self.showFirstHint ? 136.kbScaled : 58.kbScaled)
        .allowsHitTesting(false)
        .onAppear {
          guard !self.hasSeenHint else { return }
          self.hasSeenHint = true
          self.showFirstHint = true
          Task { @MainActor in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self.showFirstHint = false
          }
        }
        .accessibilityLabel("Long recording, \(seconds) seconds. Transcription time depends on device performance.")
      }
    }
  }
}
