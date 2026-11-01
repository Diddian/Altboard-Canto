import SwiftUI

struct CustomQwenModelView: View {
  @EnvironmentObject private var downloadService: ModelDownloadService
  @State private var variant: ModelVariant = .qwen3ASR17B
  @State private var repositoryID = CustomQwenModelSource.repositoryID(for: .qwen3ASR17B)
  @State private var status: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Offline Qwen3-ASR", systemImage: "waveform").font(.headline)
      Text("Built-in model downloads from Hugging Face, automatically retrying each file on HF-Mirror. No API key or model URL required.")
        .font(.footnote).foregroundStyle(.secondary)

      Picker("Model size", selection: self.$variant) {
        Text("Qwen3 0.6B — smaller").tag(ModelVariant.qwen3ASR06B)
        Text("Qwen3 1.7B — higher quality").tag(ModelVariant.qwen3ASR17B)
      }
      .pickerStyle(.menu)

      if !self.variant.isSupportedOnCurrentDevice {
        Label("This model exceeds the configured device RAM limit.", systemImage: "exclamationmark.triangle")
          .font(.footnote).foregroundStyle(.orange)
      }

      Menu {
        ForEach(CustomQwenModelSource.presets(for: self.variant), id: \.self) { source in
          Button(source) { self.repositoryID = source }
        }
      } label: {
        Label("Choose free Hugging Face source", systemImage: "server.rack")
      }

      TextField("Hugging Face model URL or owner/repository", text: self.$repositoryID)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .keyboardType(.URL)
        .textFieldStyle(.roundedBorder)

      Text("Custom import accepts sherpa-onnx Qwen3-ASR repositories only. MLX, GGUF, general Whisper and arbitrary Hugging Face files are not compatible.")
        .font(.caption).foregroundStyle(.secondary)

      Button {
        guard CustomQwenModelSource.save(self.repositoryID, for: self.variant) else {
          self.status = "Enter a valid public Hugging Face repository."
          return
        }
        self.status = "Source saved. Starting download; keep Altboard open during large downloads."
        self.downloadService.startDownload(variant: self.variant)
      } label: {
        Label("Save source and download", systemImage: "arrow.down.circle.fill")
      }
      .disabled(CustomQwenModelSource.normalizedRepositoryID(self.repositoryID) == nil
                || !self.variant.isSupportedOnCurrentDevice
                || self.downloadService.isDownloaded(self.variant))

      if let status {
        Text(status).font(.footnote).foregroundStyle(.secondary)
      }
      Text("Detected device RAM: \(ProcessInfo.processInfo.physicalMemory / 1_000_000_000) GB. Storage and free app memory are also checked; 1.7B is experimental.")
        .font(.caption).foregroundStyle(.secondary)
    }
    .padding(12)
    .background(Color(.secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .onChange(of: self.variant) { _, choice in
      self.repositoryID = CustomQwenModelSource.repositoryID(for: choice)
      self.status = nil
    }
  }
}
