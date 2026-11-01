import SwiftUI

struct CantoneseCorrectionsView: View {
  @State private var rules = SharedSettings().cantoneseCorrectionRules
  @State private var misheard = ""
  @State private var correct = ""
  @State private var sampleText = ""
  @State private var saveStatus: String?

  var body: some View {
    Form {
      Section {
        TextField("Heard, e.g. 餵你", text: self.$misheard)
          .textInputAutocapitalization(.never)
        TextField("Write, e.g. 喂你", text: self.$correct)
          .textInputAutocapitalization(.never)
        Button("Save correction", action: self.addRule)
          .disabled(!self.canAdd)
        if let saveStatus {
          Text(saveStatus)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Teach a phrase")
      } footer: {
        Text("Use a phrase of at least two characters, including context. Commas and spaces in the recognized text may vary. Exact phrase replacement is independent of AI Cleanup.")
      }

      Section {
        TextField("Paste or type recognized text", text: self.$sampleText, axis: .vertical)
          .lineLimit(2...4)
        if !self.sampleText.isEmpty {
          LabeledContent("Result") {
            Text(self.preview.text)
              .multilineTextAlignment(.trailing)
          }
          Text(self.preview.matchedRules > 0
            ? "\(self.preview.matchedRules) saved correction match(es)."
            : "No saved rule matched. Try the exact words from the ASR result.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      } header: {
        Text("Test your saved corrections")
      } footer: {
        Text("This runs the same offline correction engine as dictation. It shows whether a rule matches before you record another message.")
      }

      Section {
        if self.rules.isEmpty {
          Text("No personal corrections yet").foregroundStyle(.secondary)
        } else {
          ForEach(self.rules) { rule in
            VStack(alignment: .leading, spacing: 4) {
              Text(rule.heard).foregroundStyle(.secondary)
              Label(rule.intended, systemImage: "arrow.turn.down.right")
            }
          }
          .onDelete(perform: self.deleteRules)
        }
      } header: {
        Text("Saved corrections")
      } footer: {
        Text("Saved on this device and applied before optional cleanup or translation. This changes text, not Qwen3's model weights.")
      }
    }
    .navigationTitle("Cantonese Corrections")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { self.rules = SharedSettings().cantoneseCorrectionRules }
  }

  private var preview: CantoneseCorrectionResult {
    CantoneseCorrections.applyDetailed(self.sampleText, customRules: self.rules)
  }

  private var trimmedHeard: String {
    self.misheard.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var trimmedCorrect: String {
    self.correct.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canAdd: Bool {
    (2...80).contains(self.trimmedHeard.count)
      && (1...80).contains(self.trimmedCorrect.count)
      && self.trimmedHeard != self.trimmedCorrect
      && (self.rules.count < 50 || self.rules.contains { $0.heard == self.trimmedHeard })
  }

  private func addRule() {
    guard self.canAdd else { return }
    var next = self.rules
    next.removeAll { $0.heard == self.trimmedHeard }
    next.append(CantoneseCorrectionRule(heard: self.trimmedHeard, intended: self.trimmedCorrect))
    guard self.persist(next) else { return }
    self.misheard = ""
    self.correct = ""
  }

  private func deleteRules(at offsets: IndexSet) {
    var next = self.rules
    next.remove(atOffsets: offsets)
    _ = self.persist(next)
  }

  @discardableResult
  private func persist(_ next: [CantoneseCorrectionRule]) -> Bool {
    guard AppGroup.sharedDefaults != nil else {
      self.saveStatus = "Shared storage unavailable. The correction was not saved."
      return false
    }
    let settings = SharedSettings()
    settings.cantoneseCorrectionRules = next
    settings.synchronize()
    let loaded = settings.cantoneseCorrectionRules
    guard loaded == next else {
      self.saveStatus = "Unable to verify saved correction. Try reopening Altboard."
      return false
    }
    self.rules = loaded
    self.saveStatus = "Saved \(loaded.count) correction(s). Test a phrase below."
    return true
  }
}
