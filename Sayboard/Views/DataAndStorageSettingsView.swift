import SwiftUI

/// All user-owned local recordings and correction data are organized here.
/// Clearing voice notes does not touch meetings, models or learned words.
struct DataAndStorageSettingsView: View {
  var body: some View {
    Form {
      Section("Recordings") {
        NavigationLink {
          HistoryStorageSettingsView()
        } label: {
          Label("Voice Notes & Retention", systemImage: "waveform")
        }
        NavigationLink {
          MeetingRecordsView()
        } label: {
          Label("Meetings", systemImage: "person.3")
        }
      }
      Section("Offline Models") {
        NavigationLink {
          ModelsView()
        } label: {
          Label("Speech Recognition Models", systemImage: "waveform.circle")
        }
        NavigationLink {
          LLMModelsScreen()
        } label: {
          Label("Text & Translation Models", systemImage: "cpu")
        }
      }
      Section {
        NavigationLink {
          CantoneseCorrectionsView()
        } label: {
          Label("Speech Recognition Corrections", systemImage: "text.badge.checkmark")
        }
        NavigationLink {
          LearningDataSettingsView()
        } label: {
          Label("Learned Suggestions & JSON Export", systemImage: "square.and.arrow.up")
        }
      } header: {
        Text("Personal Vocabulary")
      } footer: {
        Text("Voice notes, meetings, correction rules and learned suggestions are managed separately. Nothing is uploaded automatically.")
      }
    }
    .navigationTitle("History & Storage")
    .navigationBarTitleDisplayMode(.inline)
  }
}
