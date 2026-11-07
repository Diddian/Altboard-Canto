import SwiftUI

/// One destination for explicit speech fixes and spoken phrase replacement.
/// Existing data stores and matching rules remain independent.
struct WordCorrectionsView: View {
  var body: some View {
    Form {
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
    .navigationTitle("Word Corrections")
    .navigationBarTitleDisplayMode(.inline)
  }
}
