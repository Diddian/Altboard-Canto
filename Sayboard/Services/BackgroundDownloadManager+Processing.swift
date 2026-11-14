
import Foundation

import ZIPFoundation

extension BackgroundDownloadManager {

  func reconcileMetadataWithTasks(_ tasks: [URLSessionTask], sessionIdentifier: String?) {
    self.lock.lock()
    guard !self.metadataReadBlocked else {
      self.lock.unlock()
      return
    }

    let activeTaskIds = Set(tasks.map(\.taskIdentifier))
    let reportingSession = sessionIdentifier ?? Self.sessionIdentifier
    var unknownTasks = [URLSessionTask]()

    // Recover the actual URLSession tasks as well as their metadata so that
    // Cancel still works after process death. Never infer ownership by URL alone.
    for task in tasks {
      if let (key, _) = self.findMetadata(
        sessionIdentifier: reportingSession, taskIdentifier: task.taskIdentifier
      ), let download = task as? URLSessionDownloadTask {
        self.activeTasks[key] = download
      } else {
        unknownTasks.append(task)
      }
    }

    for (key, meta) in self.activeMetadata {
      guard (meta.sessionIdentifier ?? Self.sessionIdentifier) == reportingSession else { continue }
      guard let taskId = meta.taskIdentifier else {
        self.activeMetadata.removeValue(forKey: key)
        self.activeTasks.removeValue(forKey: key)
        continue
      }
      guard !activeTaskIds.contains(taskId),
            !self.installingTasks.contains(self.installationID(meta)) else { continue }

      // A folder existing on disk is not proof of checksum verification. Do
      // not publish a false completed event for a missing system task.
      self.lastFinishedTasks[key] = self.installationID(meta)
      self.emit(.failed(
        downloadType: meta.downloadType,
        variantRawValue: meta.variantRawValue,
        error: R2DownloadError.cancelled
      ), key: key, metadata: meta, terminal: true)
      self.activeMetadata.removeValue(forKey: key)
      self.activeTasks.removeValue(forKey: key)
    }
    self.persistMetadata()
    self.lock.unlock()

    if !unknownTasks.isEmpty {
      AppGroup.sharedDefaults?.set(true, forKey: Self.recoveryNoticeKey)
      FeatureDiagnostics.record(.speechModel, .fallback)
      // Without a verified source, expected digest or destination, resuming
      // unknown tasks would risk installing unverifiable model bytes.
      for task in unknownTasks { task.cancel() }
    }
  }

  func processDownloadedFile(tempURL: URL, key: String, metadata: DownloadMetadata) {
    let fm = FileManager.default
    defer {
      self.lock.lock()
      self.installingTasks.remove(self.installationID(metadata))
      self.lock.unlock()
    }

    self.lock.lock()
    let stillActive = self.isCurrent(key: key, metadata: metadata)
    self.lock.unlock()
    guard stillActive else {
      try? fm.removeItem(at: tempURL)
      return
    }

    if let verifyError = self.verifySHA256(of: tempURL, expected: metadata.expectedSHA256) {
      try? fm.removeItem(at: tempURL)
      self.completeWithFailure(key: key, metadata: metadata, error: verifyError)
      return
    }

    let rawGGUFName: String?
    if metadata.downloadType != .stt, metadata.sourceURL.pathExtension.lowercased() == "gguf" {
      rawGGUFName = LLMModelVariant(rawValue: metadata.variantRawValue)?.ggufFileName
      guard rawGGUFName != nil else {
        try? fm.removeItem(at: tempURL)
        self.completeWithFailure(key: key, metadata: metadata, error: R2DownloadError.cancelled)
        return
      }
    } else {
      rawGGUFName = nil
    }
    if let extractError = self.extractToDestination(
      zipURL: tempURL, destinationDir: metadata.destinationDirectory, ggufFileName: rawGGUFName,
      key: key, metadata: metadata
    ) {
      self.completeWithFailure(key: key, metadata: metadata, error: extractError)
      return
    }

    self.completeWithSuccess(key: key, metadata: metadata)
  }

  private static func volumeIsFull() -> Bool {
    guard let freeBytes = DiskSpace.availableBytes() else { return false }
    return freeBytes < 100_000_000
  }

  private func verifySHA256(of fileURL: URL, expected: String) -> R2DownloadError? {
    do {
      let actualHash = try Self.computeSHA256(of: fileURL)
      guard actualHash == expected.lowercased() else {
        return .sha256Mismatch(expected: expected, actual: actualHash)
      }
      return nil
    } catch {
      return .downloadFailed(error)
    }
  }

  private func extractToDestination(zipURL: URL, destinationDir: URL,
                                    ggufFileName: String? = nil,
                                    key: String, metadata: DownloadMetadata) -> R2DownloadError? {
    let fm = FileManager.default
    do {
      try ModelDownloadInstaller.install(
        source: zipURL, destination: destinationDir, ggufFileName: ggufFileName
      ) { staging in
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.isCurrent(key: key, metadata: metadata) else {
          throw R2DownloadError.cancelled
        }
        try ModelDownloadInstaller.promote(staging: staging, destination: destinationDir)
      }

      return nil
    } catch {
      let ranOutOfSpace = Self.volumeIsFull()
      try? fm.removeItem(at: zipURL)
      return ranOutOfSpace ? .extractionRanOutOfSpace : .extractionFailed(error)
    }
  }

  private func completeWithSuccess(key: String, metadata: DownloadMetadata) {
    self.lock.lock()
    guard self.isCurrent(key: key, metadata: metadata) else {
      self.lock.unlock()
      return
    }
    self.lastFinishedTasks[key] = self.installationID(metadata)
    self.activeMetadata.removeValue(forKey: key)
    self.activeTasks.removeValue(forKey: key)
    self.lastProgress.removeValue(forKey: key)
    self.persistMetadata()
    self.lock.unlock()

    let event = DownloadEvent.completed(
      downloadType: metadata.downloadType,
      variantRawValue: metadata.variantRawValue,
      destinationDirectory: metadata.destinationDirectory,
    )
    self.emit(event, key: key, metadata: metadata, terminal: true)
  }
}


