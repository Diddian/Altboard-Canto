import SwiftUI

/// Model source settings use normal Altboard navigation. Model installation and
/// progress remain in the standard ModelCardView on the Models screen.
struct CustomQwenModelView: View {

  @EnvironmentObject private var downloadService: ModelDownloadService
  @Environment(\.dismiss) private var dismiss

  @State private var repositoryID = CustomQwenModelSource.repositoryID(for: .qwen3ASR17B)
  @State private var message: String?

  private let variant = ModelVariant.qwen3ASR17B

  var body: some View {
    Form {
      Section {
        LabeledContent("Model", value: self.variant.displayName)
        Menu {
          ForEach(CustomQwenModelSource.presets(for: self.variant), id: \.self) { source in
            Button(source) { self.repositoryID = source }
          }
        } label: {
          HStack {
            Text("Known free sources")
            Spacer()
            Image(systemName: "chevron.up.chevron.down")
              .foregroundStyle(.secondary)
          }
        }

        TextField("Hugging Face owner/repository or URL", text: self.$repositoryID)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .keyboardType(.URL)

        Button("Save Source") {
          guard CustomQwenModelSource.save(self.repositoryID, for: self.variant) else {
            self.message = "Enter a valid Hugging Face model repository."
            return
          }
          self.dismiss()
        }
        .disabled(
          CustomQwenModelSource.normalizedRepositoryID(self.repositoryID) == nil
            || self.isBusyOrInstalled
        )

        if let message {
          Text(message)
            .font(.footnote)
            .foregroundStyle(.orange)
        }
      } header: {
        Text("Qwen3-ASR 1.7B")
      } footer: {
        Text("Download, progress, Cancel and Retry are on the Qwen model card. Sources must provide sherpa-onnx Qwen3-ASR ONNX files.")
      }

      if self.isBusyOrInstalled {
        Section {
          Label(
            "Cancel the download or remove the installed model before changing its source.",
            systemImage: "info.circle"
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
    }
    .navigationTitle("Model Source")
    .navigationBarTitleDisplayMode(.inline)
  }

  private var isBusyOrInstalled: Bool {
    switch self.downloadService.state(for: self.variant) {
    case .downloading, .downloaded: true
    case .notDownloaded, .error: false
    }
  }
}
