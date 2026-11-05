import Foundation

/// Revision-pinned GGUF downloads verified against the publisher's LFS metadata.
enum HereticModelCatalog {
  static func entry(for variant: LLMModelVariant) -> LLMModelEntry? {
    switch variant {
    case .hereticBalanced:
      LLMModelEntry(
        url: URL(string: "https://huggingface.co/Abiray/Qwen3.5-2B-heretic-GGUF/resolve/2393e0e7c17a1aec735a7539378cf0defe9c345e/Qwen3.5-2B-heretic-Q4_K_M.gguf")!,
        sha256: "dad8a69dddcd64f2221dd06ae5c46baceb31ed9bd0dec330306d77762c377cf1", sizeBytes: 1270807936,
        minLlamaBuild: 9180, expandedBytes: 0
      )
    case .hereticLarge:
      LLMModelEntry(
        url: URL(string: "https://huggingface.co/DavidAU/Qwen3.5-9B-The-Defiant-Fable-Uncensored-Heretic-NEO-IMATRIX-MAX-MTP-GGUF/resolve/d5f3139249b7ee2535c20ab81125c9a6ab0c4915/Qwen3.5-9B-The-Defiant-Fable-Uncnr-Heretic-NEO-MAX-MTP-IQ3_M.gguf")!,
        sha256: "726ad4c6c41906e314052e69a294ae3372310c8d11c2e78d4e97784d5beec110", sizeBytes: 5722667232,
        minLlamaBuild: 9180, expandedBytes: 0
      )
    case .hereticSmall:
      LLMModelEntry(
        url: URL(string: "https://huggingface.co/mradermacher/Qwen3.5-0.8B-heretic-v3-i1-GGUF/resolve/70f31ab0b00c626aacd0b4c64b32ce43640360a9/Qwen3.5-0.8B-heretic-v3.i1-Q4_K_M.gguf")!,
        sha256: "3c1a21ee949303cbb65e8a8380ffa17161901680080e12e08c397528e110c0d1", sizeBytes: 529298208,
        minLlamaBuild: 9180, expandedBytes: 0
      )
    default: nil
    }
  }
}
