import SwiftUI
import UIKit

/// Read-only visibility into Cantonese learning; never exports the words used.
struct CantoneseRomanizationDiagnosticsView: View {
  @State private var evidence = [String: Int]()
  @State private var groupAvailable = false
  @State private var hasLearningData = false
  @State private var storedCandidates = 0
  @State private var storedSelectionWeight = 0
  @State private var shareFile: RomanizationDiagnosticFile?
  @State private var temporaryExportURL: URL?
  @State private var exportError = ""
  @State private var showsExportError = false

  var body: some View {
    Form {
      Section("Learned Romanization") {
        LabeledContent("State", value: self.stateDescription)
        LabeledContent("Preferred spelling", value:
          CantoneseSchemePreference.preferred(self.evidence) ?? "Not established")
        LabeledContent("Search priority", value:
          CantoneseSchemePreference.lookupOrder(self.evidence).joined(separator: " → "))
        LabeledContent("唔 typed as", value:
          CantoneseSchemePreference.prefersColloquialNg(self.evidence)
            ? "ng preferred" : "m / undecided")
      }
      Section {
        ForEach(CantoneseSchemePreference.evidenceKeys, id: \.self) { key in
          LabeledContent(self.displayName(for: key),
                         value: String(max(0, self.evidence[key] ?? 0)))
        }
        LabeledContent("Saved candidate entries", value: String(self.storedCandidates))
        LabeledContent("Saved selection weight", value: String(self.storedSelectionWeight))
        Button("Refresh Counts") { self.refresh() }
      } header: {
        Text("Recent Weighted Selections")
      } footer: {
        Text("Counts are based on confirmed selections, not every keystroke. Older evidence gradually loses weight. Identical spellings can be shared by multiple systems.")
      }
      Section("Export") {
        Button {
          self.shareDiagnostics()
        } label: {
          Label("Share Diagnostic JSON", systemImage: "square.and.arrow.up")
        }
        Button {
          self.copyDiagnostics()
        } label: {
          Label("Copy Diagnostic JSON", systemImage: "doc.on.doc")
        }
        Text("Exports aggregated counts, ranking, and build identifiers only. No typed text, candidate words, conversations, host contents, or recordings are included. Nothing is uploaded automatically.")
          .font(.footnote)
          .foregroundStyle(.secondary)
      }
    }
    .navigationTitle("Cantonese Learning")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { self.refresh() }
    .sheet(item: self.$shareFile, onDismiss: {
      if let url = self.temporaryExportURL {
        try? FileManager.default.removeItem(at: url)
        self.temporaryExportURL = nil
      }
    }) { file in
      RomanizationDiagnosticShareSheet(url: file.url)
    }
    .alert("Diagnostic Export Failed", isPresented: self.$showsExportError) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(self.exportError)
    }
  }

  private var stateDescription: String {
    if !self.groupAvailable { return "App Group unavailable" }
    return self.hasLearningData ? "Learning" : "No confirmed selections yet"
  }

  private func displayName(for key: String) -> String {
    switch key {
    case "plain": return "Jyutping"
    case "yale": return "Yale"
    case "sidney": return "Sidney Lau"
    case "traditional": return "Shared j / ch"
    case "negative_ng": return "唔 as ng"
    case "negative_m": return "唔 as m"
    default: return "Other"
    }
  }

  private func refresh() {
    let defaults = AppGroup.sharedDefaults
    self.groupAvailable = defaults != nil
    self.evidence = defaults?.dictionary(
      forKey: CantoneseSchemePreference.preferenceStorageKey
    ) as? [String: Int] ?? [:]
    self.hasLearningData = self.evidence.values.contains { $0 > 0 }
    let saved = defaults?.dictionary(
      forKey: CantoneseSchemePreference.candidateStorageKey
    ) as? [String: Int] ?? [:]
    self.storedCandidates = saved.count
    self.storedSelectionWeight = saved.values.reduce(0) {
      $0 + min(10_000, max(0, $1))
    }
  }

  private func reportData() throws -> Data {
    let defaults = AppGroup.sharedDefaults
    let counts = defaults?.dictionary(
      forKey: CantoneseSchemePreference.preferenceStorageKey
    ) as? [String: Int] ?? [:]
    let candidateCounts = defaults?.dictionary(
      forKey: CantoneseSchemePreference.candidateStorageKey
    ) as? [String: Int] ?? [:]
    return try CantoneseSchemePreference.diagnosticJSON(
      counts: counts,
      candidateCounts: candidateCounts,
      groupAvailable: defaults != nil,
      preferenceDataPresent: defaults?.object(
        forKey: CantoneseSchemePreference.preferenceStorageKey
      ) != nil,
      appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
      appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
      appCommit: Bundle.main.infoDictionary?["AltboardBuildSHA"] as? String ?? "unstamped",
      keyboardCommit: defaults?.string(forKey: SharedKey.keyboardBuildSHA) ?? "not reported",
      generatedAt: Date()
    )
  }

  private func shareDiagnostics() {
    do {
      let data = try self.reportData()
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "AltBoard-Cantonese-Romanization-\(UUID().uuidString).json"
      )
      try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
      self.temporaryExportURL = url
      self.shareFile = RomanizationDiagnosticFile(url: url)
      self.refresh()
    } catch {
      self.reportError(error)
    }
  }

  private func copyDiagnostics() {
    do {
      let data = try self.reportData()
      guard let text = String(data: data, encoding: .utf8) else { return }
      UIPasteboard.general.string = text
      self.refresh()
    } catch {
      self.reportError(error)
    }
  }

  private func reportError(_ error: Error) {
    self.exportError = error.localizedDescription
    self.showsExportError = true
  }
}

private struct RomanizationDiagnosticFile: Identifiable {
  let id = UUID()
  let url: URL
}

private struct RomanizationDiagnosticShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [self.url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
