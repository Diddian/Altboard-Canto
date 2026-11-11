
import Combine
import Foundation

import UIKit

extension ModelDownloadService {

  func subscribeToDownloadEvents() {
    self.eventCancellable = BackgroundDownloadManager.shared.eventSubject
      .filter { event in
        switch event {
        case .progress(let type, _, _): type == .stt
        case .completed(let type, _, _): type == .stt
        case .failed(let type, _, _): type == .stt
        }
      }
      .receive(on: DispatchQueue.main)
      .sink { [weak self] event in
        self?.handleDownloadEvent(event)
      }
  }

  func enqueueDownload(variant: ModelVariant, generation: UUID) async {
    defer {
      if self.enqueueGenerations[variant] == generation {
        self.enqueueTasks[variant] = nil
        self.enqueueGenerations[variant] = nil
      }
    }
    if variant.engine == .qwen3 || variant.engine == .senseVoice {
      do {
        if variant.engine == .senseVoice {
          try await SenseVoiceModelDownloader.download { [weak self] fraction in
            guard let self, self.enqueueGenerations[variant] == generation,
                  !Task.isCancelled else { return }
            self.variantStates[variant] = .downloading(progress: min(fraction * 0.95, 0.95))
          }
        } else {
          try await QwenHubDownloader.download(variant: variant) { [weak self] fraction in
            guard let self, self.enqueueGenerations[variant] == generation,
                  !Task.isCancelled else { return }
            guard case .downloading = self.state(for: variant) else { return }
            self.variantStates[variant] = .downloading(
              progress: min(max(fraction, 0) * Self.downloadProgressCeiling, Self.downloadProgressCeiling)
            )
          }
        }
        try Task.checkCancellation()
        guard ModelStorageManager.isDownloaded(variant) else {
          throw QwenHubDownloader.DownloadError.incompatible("Downloaded speech model files were not verified")
        }
        // Use the same preparing-model progress phase as every other model.
        let modelReady = await self.loadModelAfterDownload(variant: variant)
        guard !Task.isCancelled, self.enqueueGenerations[variant] == generation else { return }
        guard modelReady else {
          self.removeVariantFromPersistence(variant)
          self.enqueueTasks[variant] = nil
          return
        }
        self.variantStates[variant] = .downloaded
        FeatureDiagnostics.record(.speechModel, .downloaded)
        self.removeVariantFromPersistence(variant)
        self.autoSelectIfNeeded(variant: variant)
      } catch {
        guard self.enqueueGenerations[variant] == generation else { return }
        FeatureDiagnostics.record(.speechModel, Task.isCancelled ? .cancelled : .failed)
        self.variantStates[variant] = Task.isCancelled ? .notDownloaded
          : .error(message: "Speech model download failed: \(error.localizedDescription)")
        self.removeVariantFromPersistence(variant)
      }
      self.enqueueTasks[variant] = nil
      return
    }

    do {
      let manifest = try await self.fetchManifestCached()
      guard let entry = manifest.entry(for: variant) else {
        throw R2DownloadError.manifestMissingVariant(variant.rawValue)
      }

      let requiredBytes = ModelDiskReserve.requiredBytes(peak: entry.peakDiskBytes)
      if let available = ModelDiskReserve.availableBytes(), available < requiredBytes {
        throw R2DownloadError.insufficientDiskSpace
      }

      try ModelStorageManager.ensureRootExists()
      let destDir = ModelStorageManager.directory(for: variant)

      let metadata = DownloadMetadata(
        downloadType: .stt,
        variantRawValue: variant.rawValue,
        expectedSHA256: entry.sha256,
        sourceURL: entry.url,
        destinationDirectory: destDir,
        sizeBytes: entry.sizeBytes,
      )

      try Task.checkCancellation()
      guard self.enqueueGenerations[variant] == generation else { return }
      BackgroundDownloadManager.shared.enqueueDownload(metadata: metadata)
    } catch {
      guard self.enqueueGenerations[variant] == generation else { return }
      FeatureDiagnostics.record(.speechModel, .failed)
      self.variantStates[variant] = .error(message: localizedDownloadError(error))
      self.removeVariantFromPersistence(variant)
    }
  }

  func loadModelAfterDownload(variant: ModelVariant) async -> Bool {
    guard let modelLoader else {
      FeatureDiagnostics.record(.speechModel, .unavailable)
      return false
    }

    guard let modelFolder = self.modelFolderURL(for: variant) else {
      FeatureDiagnostics.record(.speechModel, .failed)
      try? ModelStorageManager.delete(variant)
      self.variantStates[variant] = .error(
        message: "Model failed to load. Tap Retry to try again."
      )
      self.removeVariantFromPersistence(variant)
      return false
    }

    if modelLoader.isModelInUse { return true }
    let ceiling = Self.downloadProgressCeiling
    self.variantStates[variant] = .downloading(progress: ceiling)

    let animationTask = Task {
      var current = ceiling
      while !Task.isCancelled, current < 0.99 {
        try? await Task.sleep(for: .milliseconds(Self.loadingAnimationIntervalMs))
        guard !Task.isCancelled else { break }
        current = min(current + Self.loadingAnimationStep, 0.99)
        self.variantStates[variant] = .downloading(progress: current)
      }
    }

    let loaded = await modelLoader.loadModel(variant: variant, from: modelFolder)
    animationTask.cancel()

    if !loaded {
      // Verified files remain downloaded; memory and worker availability are transient.
      FeatureDiagnostics.record(.speechModel, .fallback)
    }
    return true
  }

  private func handleDownloadEvent(_ event: DownloadEvent) {
    switch event {
    case .progress(_, let variantRawValue, let fraction):
      guard let variant = ModelVariant(rawValue: variantRawValue) else { return }
      let capped = min(fraction, Self.downloadProgressCeiling)
      self.variantStates[variant] = .downloading(progress: capped)

    case .completed(_, let variantRawValue, _):
      guard let variant = ModelVariant(rawValue: variantRawValue) else { return }
      self.enqueueTasks[variant] = nil
      Task {
        let modelReady = await self.loadModelAfterDownload(variant: variant)
        guard modelReady else { return }
        self.variantStates[variant] = .downloaded
        FeatureDiagnostics.record(.speechModel, .downloaded)
        self.removeVariantFromPersistence(variant)
        self.autoSelectIfNeeded(variant: variant)
      }

    case .failed(_, let variantRawValue, let error):
      guard let variant = ModelVariant(rawValue: variantRawValue) else { return }
      FeatureDiagnostics.record(.speechModel, .failed)
      self.enqueueTasks[variant] = nil
      self.variantStates[variant] = .error(message: localizedDownloadError(error))
      self.removeVariantFromPersistence(variant)
    }
  }

  private func fetchManifestCached() async throws -> ModelManifest {
    if let cached = self.cachedManifest {
      return cached
    }
    let manifest = try await ManifestFetcher.fetch()
    self.cachedManifest = manifest
    return manifest
  }
}

func localizedDownloadError(_ error: Error) -> LocalizedStringResource {
  if case R2DownloadError.appTooOldForModel = error {
    return "Update Altboard to use this model."
  }
  if isOutOfSpaceError(error) {
    return "Not enough storage space. Free up space and try again."
  }
  if let modelError = error as? R2DownloadError {
    return "Model download: \(modelError.localizedDescription)"
  }
  if let manifestError = error as? ManifestError {
    return "Model catalog: \(manifestError.localizedDescription)"
  }
  let nsError = error as NSError
  if nsError.domain == NSURLErrorDomain {
    switch nsError.code {
    case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
      return "No internet connection. Check your network and try again."
    case NSURLErrorTimedOut:
      return "Download timed out. Try again later."
    default:
      return "Network error (\(nsError.code)). Check your connection and try again."
    }
  }
  return "Download failed. Tap Retry to try again."
}

private func isOutOfSpaceError(_ error: Error) -> Bool {
  let posixStorageFull = 28

  func matches(_ error: Error, depth: Int) -> Bool {
    guard depth <= 4 else { return false }

    switch error {
    case R2DownloadError.extractionRanOutOfSpace, R2DownloadError.insufficientDiskSpace:
      return true
    case R2DownloadError.extractionFailed(let underlying), R2DownloadError.downloadFailed(let underlying):
      if matches(underlying, depth: depth + 1) { return true }
    default:
      break
    }

    let nsError = error as NSError
    if nsError.domain == NSPOSIXErrorDomain, nsError.code == posixStorageFull { return true }
    if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteOutOfSpaceError { return true }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
      return matches(underlying, depth: depth + 1)
    }
    return false
  }

  return matches(error, depth: 0)
}

