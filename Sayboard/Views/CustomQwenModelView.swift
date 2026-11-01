import SwiftUI

struct CustomQwenModelView: View {
  @State private var url = CustomQwenModelSource.url
  @State private var digest = CustomQwenModelSource.sha256
  @EnvironmentObject private var downloadService: ModelDownloadService
  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Qwen3-ASR 1.7B (experimental ONNX)").font(.headline)
      Text("Custom HTTPS URL for a sherpa-onnx Qwen3-ASR ZIP archive. MLX/Hugging Face model folders are not compatible. Require a SHA-256 digest before downloading.")
        .font(.footnote).foregroundStyle(.secondary)
      TextField("https://host/model-onnx.zip", text: $url).textInputAutocapitalization(.never)
        .keyboardType(.URL).autocorrectionDisabled()
      TextField("SHA-256 (64 hex characters)", text: $digest).textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      Button("Save Qwen3 model source") {
        CustomQwenModelSource.url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        CustomQwenModelSource.sha256 = digest.trimmingCharacters(in: .whitespacesAndNewlines)
      }.disabled(URL(string: url)?.scheme != "https" || digest.count != 64)
      Text("After saving, use the Qwen3 model card below to download and select it.")
        .font(.footnote).foregroundStyle(.secondary)
    }.padding(12).background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
  }
}
