import SwiftUI

struct CantoneseCorrectionsView: View {
  @State private var rules = SharedSettings().cantoneseCorrectionRules
  @State private var misheard = ""
  @State private var correct = ""

  var body: some View {
    Form {
      Section {
        TextField("Recognized phrase, e.g. 餵，你", text: self.$misheard)
          .textInputAutocapitalization(.never)
        TextField("Correct phrase, e.g. 喂，你", text: self.$correct)
          .textInputAutocapitalization(.never)
        Button("Save correction", action: self.addRule)
          .disabled(!self.canAdd)
      } header: {
        Text("Teach a phrase")
      } footer: {
        Text("Use at least two characters and include surrounding words. For example, correcting 餵，你 is safer than changing every 餵, which would also change 餵食.")
      }

      Section {
        if self.rules.isEmpty {
          Text("No personal corrections yet")
            .foregroundStyle(.secondary)
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
        Text("Saved only on this device. Applied to future dictation results, before translation or cleanup. This is phrase replacement, not model fine-tuning.")
      }
    }
    .navigationTitle("Cantonese Corrections")
    .navigationBarTitleDisplayMode(.inline)
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
    self.rules.removeAll { $0.heard == self.trimmedHeard }
    self.rules.append(CantoneseCorrectionRule(heard: self.trimmedHeard, intended: self.trimmedCorrect))
    self.persist()
    self.misheard = ""
    self.correct = ""
  }

  private func deleteRules(at offsets: IndexSet) {
    self.rules.remove(atOffsets: offsets)
    self.persist()
  }

  private func persist() {
    SharedSettings().cantoneseCorrectionRules = self.rules
  }
}
