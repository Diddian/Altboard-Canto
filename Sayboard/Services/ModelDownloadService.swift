
import Combine
import Foundation

@MainActor
final class ModelDownloadService: ObservableObject {

  init() {
    self.migrateFromHuggingFaceIfNeeded()
    self.verifyExistingModels()
    self.subscribeToDownloadEvents()
  }

  static let downloadProgressCeiling = 0.95

  static let loadingAnimationStep = 0.001
  static let loadingAnimationIntervalMs = 200

  @Published var variantStates = [ModelVariant: ModelDownloadState]()
  @Published var selectedVariant: ModelVariant = SharedSettings().selectedVariant

  weak var modelLoader: (any ModelLoading)?

  var cachedManifest: ModelManifest?

  var eventCancellable: AnyCancellable?
  var enqueueTasks = [ModelVariant: Task<Void, Never>]()

  var hasUsableModel: Bool {
    self.isDownloaded(SharedSettings().selectedVariant)
  }

  var activeModelFolderURL: URL? {
    let selected = SharedSettings().selectedVariant
    return self.modelFolderURL(for: selected)
  }

  var downloadedVariants: Set<ModelVariant> {
    Set(ModelVariant.allCases.filter { self.isDownloaded($0) })
  }

  func state(for variant: ModelVariant) -> ModelDownloadState {
    self.variantStates[variant] ?? .notDownloaded
  }

  func isDownloaded(_ variant: ModelVariant) -> Bool {
    self.state(for: variant) == .downloaded
  }

  func selectVariant(_ variant: ModelVariant) {
    guard !MeetingRecordingCoordinator.shared.isRecording,
          !MeetingRecordingCoordinator.shared.isFinalizing,
          ConversationCoordinator.shared.recordingSide == nil,
          !ConversationCoordinator.shared.processing,
          !SharedSettings().isRecording else {
      FeatureDiagnostics.record(.speechModel, .blocked)
      return
    }
    FeatureDiagnostics.record(.speechModel, .selected)
    let settings = SharedSettings()
    settings.selectedVariant = variant
    settings.setPreferredLanguages(
      SpeechModelRecommendation.preferredLanguages(for: variant, from: settings.preferredSpokenLanguages),
      for: variant
    )
    if self.selectedVariant != variant { self.selectedVariant = variant }
    self.syncHasUsableModel()
  }

  func modelFolderURL(for variant: ModelVariant) -> URL? {
    let dir = ModelStorageManager.directory(for: variant)
    guard ModelStorageManager.isDownloaded(variant) else { return nil }

    let fm = FileManager.default
    if variant.engine == .qwen3 {
      return Qwen3ModelBundle.locate(in: dir)
    }
    let targetExtension = variant.engine == .moonshine ? "ort" : "mlmodelc"

    if
      let directContents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil),
      directContents.contains(where: { $0.pathExtension == targetExtension })
    {
      return dir
    }

    guard
      let contents = try? fm.contentsOfDirectory(
        at: dir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: .skipsHiddenFiles,
      )
    else {
      return nil
    }

    for subdir in contents {
      let isDir = (try? subdir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
      guard isDir else { continue }
      if
        let innerContents = try? fm.contentsOfDirectory(at: subdir, includingPropertiesForKeys: nil),
        innerContents.contains(where: { $0.pathExtension == targetExtension })
      {
        return subdir
      }
    }

    return nil
  }

  func verifyExistingModels() {
    var states = self.variantStates
    for variant in ModelVariant.allCases {
      switch states[variant] {
      case .downloading, .error:
        continue
      case .downloaded, .notDownloaded, .none:
        break
      }

      if ModelStorageManager.isDownloaded(variant) {
        states[variant] = .downloaded
      } else if BackgroundDownloadManager.shared.hasActiveDownload(variantRawValue: variant.rawValue, downloadType: .stt) {
        states[variant] = .downloading(progress: 0)
      } else {
        states[variant] = .notDownloaded
      }
    }
    if states != self.variantStates { self.variantStates = states }
    self.ensureValidSelection()
    self.syncHasUsableModel()
  }

  func ensureValidSelection() {
    let settings = SharedSettings()
    let current = settings.selectedVariant
    guard !self.isDownloaded(current) else {
      if self.selectedVariant != current { self.selectedVariant = current }
      return
    }
    if current == .parakeetV3, settings.parakeetV3NeedsRedownload {
      if self.selectedVariant != current { self.selectedVariant = current }
      return
    }
    if let downloaded = ModelVariant.allCases.first(where: { isDownloaded($0) }) {
      settings.selectedVariant = downloaded
      self.selectedVariant = downloaded
    }
  }

  func startDownload(variant: ModelVariant) {
    guard !MeetingRecordingCoordinator.shared.isRecording,
          !MeetingRecordingCoordinator.shared.isFinalizing,
          ConversationCoordinator.shared.recordingSide == nil,
          !ConversationCoordinator.shared.processing,
          !SharedSettings().isRecording else {
      FeatureDiagnostics.record(.speechModel, .blocked)
      self.variantStates[variant] = .error(message: "Stop recording before downloading a speech model.")
      return
    }
    if variant.engine == .qwen3 {
      // Avoid concurrent foreground tasks for the same multi-GB model.
      guard self.enqueueTasks[variant] == nil else { return }
    }
    guard
      !BackgroundDownloadManager.shared.hasActiveDownload(
        variantRawValue: variant.rawValue,
        downloadType: .stt,
      )
    else { return }

    let settings = SharedSettings()
    var variants = settings.downloadInProgressVariants
    variants.insert(variant)
    settings.downloadInProgressVariants = variants
    settings.downloadStartedAt = Date()

    self.variantStates[variant] = .downloading(progress: 0)
    FeatureDiagnostics.record(.speechModel, .queued)

    self.enqueueTasks[variant] = Task {
      await self.enqueueDownload(variant: variant)
    }
  }

  func cancelDownload(variant: ModelVariant) {
    FeatureDiagnostics.record(.speechModel, .cancelled)
    self.enqueueTasks[variant]?.cancel()
    self.enqueueTasks[variant] = nil

    BackgroundDownloadManager.shared.cancelDownload(
      variantRawValue: variant.rawValue,
      downloadType: .stt,
    )

    try? ModelStorageManager.delete(variant)

    self.variantStates[variant] = .notDownloaded
    self.removeVariantFromPersistence(variant)
  }

  func deleteModel(variant: ModelVariant) {
    guard !MeetingRecordingCoordinator.shared.isRecording,
          !MeetingRecordingCoordinator.shared.isFinalizing,
          ConversationCoordinator.shared.recordingSide == nil,
          !ConversationCoordinator.shared.processing,
          !SharedSettings().isRecording else {
      FeatureDiagnostics.record(.speechModel, .blocked)
      return
    }
    do {
      try ModelStorageManager.delete(variant)
      FeatureDiagnostics.record(.speechModel, .deleted)
    } catch {
      FeatureDiagnostics.record(.speechModel, .failed)
      let name = variant.rawValue
      DiagnosticLog.write("models: DELETE FAILED \(name): \(error)")
    }

    self.variantStates[variant] = .notDownloaded

    let settings = SharedSettings()
    if settings.selectedVariant == variant {
      let otherDownloaded = ModelVariant.allCases.first {
        $0 != variant && self.isDownloaded($0)
      }
      if let other = otherDownloaded {
        settings.selectedVariant = other
        self.selectedVariant = other
      }
    }
    self.syncHasUsableModel()
  }

  func dismissError(variant: ModelVariant) {
    self.variantStates[variant] = .notDownloaded
  }

  func resumeInterruptedDownloadIfNeeded() {
    let settings = SharedSettings()
    let interrupted = settings.downloadInProgressVariants
    guard !interrupted.isEmpty else { return }

    for variant in interrupted {
      if
        BackgroundDownloadManager.shared.hasActiveDownload(
          variantRawValue: variant.rawValue,
          downloadType: .stt,
        )
      {
        continue
      }
      self.removeVariantFromPersistence(variant)
      self.startDownload(variant: variant)
    }
  }

  func checkForInterruptedDownloadOnLaunch() {
    let settings = SharedSettings()
    let interrupted = settings.downloadInProgressVariants
    guard !interrupted.isEmpty else { return }

    let message: LocalizedStringResource = "Download was interrupted. Tap Retry to continue."
    for variant in interrupted {
      guard self.state(for: variant) != .downloaded else {
        continue
      }
      if
        BackgroundDownloadManager.shared.hasActiveDownload(
          variantRawValue: variant.rawValue,
          downloadType: .stt,
        )
      {
        continue
      }
      self.variantStates[variant] = .error(message: message)
    }
    self.clearDownloadPersistence()
    self.syncHasUsableModel()
  }

  func autoSelectIfNeeded(variant: ModelVariant) {
    let settings = SharedSettings()
    if !self.isDownloaded(settings.selectedVariant) {
      settings.selectedVariant = variant
      self.selectedVariant = variant
    }
    self.syncHasUsableModel()
  }

  func syncHasUsableModel() {
    let usable = self.hasUsableModel
    let settings = SharedSettings()
    if settings.hasUsableModel != usable { settings.hasUsableModel = usable }
  }

  func resetToNotDownloaded(variant: ModelVariant) {
    self.variantStates[variant] = .notDownloaded
  }

  func removeVariantFromPersistence(_ variant: ModelVariant) {
    let settings = SharedSettings()
    var variants = settings.downloadInProgressVariants
    variants.remove(variant)
    settings.downloadInProgressVariants = variants
    if variants.isEmpty {
      settings.downloadStartedAt = nil
    }
  }

  private func clearDownloadPersistence() {
    let settings = SharedSettings()
    settings.downloadInProgressVariants = []
    settings.downloadStartedAt = nil
  }

  private func migrateFromHuggingFaceIfNeeded() {
    LegacyModelMigration.runIfNeeded()
  }
}

