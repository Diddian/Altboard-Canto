import SwiftUI

/// Unified review and entry point for spoken phrase replacement.
/// Existing speech-correction and snippet stores retain their distinct
/// matching stages so saved user rules continue to behave as before.
struct WordCorrectionsView: View {
  private enum RuleKind: String, CaseIterable {
    case speech
    case phrase

    var label: LocalizedStringKey {
      switch self {
      case .speech: "Speech Corrections"
      case .phrase: "Phrase Replacements"
      }
    }
  }

  private struct Entry: Identifiable {
    let id: String
    let kind: RuleKind
    let heard: String
    let intended: String
  }

  @State private var kind: RuleKind = .speech
  @State private var heard = ""
  @State private var intended = ""
  @State private var rules: [CantoneseCorrectionRule] = []
  @State private var snippets: [Snippet] = []
  @State private var storageUnavailable = false

  private var combinedEntries: [Entry] {
    let speech = self.rules.map {
      Entry(id: "speech-" + $0.id.uuidString, kind: .speech,
            heard: $0.heard, intended: $0.intended)
    }
    let phrases = self.snippets.map {
      Entry(id: "phrase-" + $0.id.uuidString, kind: .phrase,
            heard: $0.trigger, intended: $0.replacement)
    }
    return speech + phrases
  }

  private var cleanHeard: String {
    self.heard.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var cleanIntended: String {
    self.intended.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canSave: Bool {
    guard !self.cleanIntended.isEmpty, !self.cleanHeard.isEmpty,
          self.cleanHeard != self.cleanIntended else { return false }
    if self.kind == .phrase { return true }
    return (2...80).contains(self.cleanHeard.count)
      && self.cleanIntended.count <= 80
      && (self.rules.count < 50 || self.rules.contains { $0.heard == self.cleanHeard })
  }

  var body: some View {
    Form {
      Section {
        Picker("Word Corrections", selection: self.$kind) {
          ForEach(RuleKind.allCases, id: \.self) { option in
            Text(option.label).tag(option)
          }
        }
        .pickerStyle(.segmented)
        TextField("What you say", text: self.$heard)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        TextField("What gets inserted", text: self.$intended)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        Button("Save correction", action: self.save)
          .disabled(!self.canSave)
        if self.storageUnavailable {
          Label("Full Access Required", systemImage: "exclamationmark.triangle")
            .font(.footnote).foregroundStyle(.orange)
        }
      }

      Section {
        if self.combinedEntries.isEmpty {
          Text("No personal corrections yet").foregroundStyle(.secondary)
        } else {
          ForEach(self.combinedEntries) { entry in
            VStack(alignment: .leading, spacing: 3) {
              Text(entry.kind.label).font(.caption).foregroundStyle(.secondary)
              Text(verbatim: entry.heard)
              Label {
                Text(verbatim: entry.intended)
              } icon: {
                Image(systemName: "arrow.turn.down.right")
              }
            }
          }
          .onDelete(perform: self.deleteEntries)
        }
      } header: {
        Text("Saved corrections")
      }

      Section {
        NavigationLink {
          CantoneseCorrectionsView()
        } label: {
          Label("Speech Corrections", systemImage: "text.badge.checkmark")
        }
        NavigationLink {
          SnippetsView()
        } label: {
          Label("Phrase Replacements", systemImage: "text.quote")
        }
      }
    }
    .navigationTitle("Word Corrections")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear(perform: self.reload)
  }

  private func reload() {
    let settings = SharedSettings()
    self.rules = settings.cantoneseCorrectionRules
    self.snippets = settings.snippets
  }

  private func save() {
    guard self.canSave, AppGroup.sharedDefaults != nil else {
      self.storageUnavailable = AppGroup.sharedDefaults == nil
      return
    }
    let settings = SharedSettings()
    if self.kind == .speech {
      var updated = settings.cantoneseCorrectionRules
      updated.removeAll { $0.heard == self.cleanHeard }
      updated.append(CantoneseCorrectionRule(heard: self.cleanHeard, intended: self.cleanIntended))
      settings.cantoneseCorrectionRules = updated
    } else {
      var updated = settings.snippets
      updated.removeAll { $0.trigger == self.cleanHeard }
      updated.append(Snippet(trigger: self.cleanHeard, replacement: self.cleanIntended))
      settings.snippets = updated
    }
    self.reload()
    self.heard = ""
    self.intended = ""
    self.storageUnavailable = false
  }

  private func deleteEntries(at offsets: IndexSet) {
    guard AppGroup.sharedDefaults != nil else {
      self.storageUnavailable = true
      return
    }
    let visible = self.combinedEntries
    let deleted = Set(offsets.compactMap { visible.indices.contains($0) ? visible[$0].id : nil })
    guard !deleted.isEmpty else { return }
    let settings = SharedSettings()
    settings.cantoneseCorrectionRules = settings.cantoneseCorrectionRules.filter {
      !deleted.contains("speech-" + $0.id.uuidString)
    }
    settings.snippets = settings.snippets.filter {
      !deleted.contains("phrase-" + $0.id.uuidString)
    }
    self.reload()
  }
}
