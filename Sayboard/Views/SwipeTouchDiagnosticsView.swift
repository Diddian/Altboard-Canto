import SwiftUI

/// Optional aggregate diagnostics; never displays or stores what was typed.
struct SwipeTouchDiagnosticsView: View {
  @AppStorage(SharedKey.keyboardSwipeDiagnosticsEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var diagnosticsEnabled = false
  @AppStorage(SharedKey.keyboardAdaptiveTouchEnabled, store: UserDefaults(suiteName: AppGroup.identifier))
  private var learningEnabled = false
  @State private var metrics = SwipeTouchMetrics()

  var body: some View {
    Form {
      Section("Swipe & Touch Settings") {
        Toggle("Swipe Diagnostics", isOn: self.$diagnosticsEnabled)
        Toggle("Learn Touch Boundaries", isOn: self.$learningEnabled)
        Text("Only a deliberate Delete followed by a neighboring correction near the key boundary is considered. Five observations are needed before any movement. Key labels never move; autocorrect is not used.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
      Section("Local Counters") {
        LabeledContent("Swipe gestures", value: "\(self.metrics.gestures)")
        LabeledContent("Recognized", value: "\(self.metrics.matchedGestures)")
        LabeledContent("Without candidates", value: "\(self.metrics.unmatchedGestures)")
        LabeledContent("Cancelled", value: "\(self.metrics.cancelledGestures)")
        LabeledContent("Stroke updates emitted", value: "\(self.metrics.emittedTrailFrames)")
        LabeledContent("Last point count", value: "\(self.metrics.lastPointCount)")
        LabeledContent("Last result", value: self.metrics.lastReason)
        LabeledContent("Adjacent tap repairs", value: "\(self.metrics.adjacentCorrections)")
        Button("Refresh Counters") { self.refresh() }
        Button("Reset Diagnostics & Touch Learning", role: .destructive) {
          KeyboardExperimentMetrics.reset()
          self.refresh()
        }
      }
    }
    .navigationTitle("Swipe & Touch Debug")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { self.refresh() }
  }

  private func refresh() {
    self.metrics = KeyboardExperimentMetrics.read()
  }
}
