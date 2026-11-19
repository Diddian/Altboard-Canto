import Foundation

struct StorageUsageSnapshot: Sendable {
  let device: DeviceStorageUsage?
  let inventory: StorageUsageInventory
  let sharedStorageUnavailable: Bool

  var isIncomplete: Bool {
    self.sharedStorageUnavailable || self.inventory.unreadableItemCount > 0
  }
}

enum StorageUsageService {
  /// Only files in the containing app's sandbox tmp directory are eligible.
  /// Protect current exports, active captures and learned App Group data.
  @MainActor
  static func deleteOldTemporaryFiles() throws -> Int {
    guard !LocalUserDataStore.hasActiveOperation else { throw CocoaError(.userCancelled) }
    let fm = FileManager.default
    let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .resolvingSymlinksInPath().standardizedFileURL
    let temporary = fm.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
    guard temporary.isFileURL, temporary.path.hasPrefix(home.path + "/") else {
      throw CocoaError(.fileWriteNoPermission)
    }
    let cutoff = Date().addingTimeInterval(-3600)
    let files = try fm.contentsOfDirectory(
      at: temporary, includingPropertiesForKeys: [
        .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey
      ])
    var deleted = 0
    for file in files {
      let values = try file.resourceValues(forKeys: [
        .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey
      ])
      guard values.isSymbolicLink != true, values.isRegularFile == true,
            let modified = values.contentModificationDate, modified < cutoff else { continue }
      try fm.removeItem(at: file)
      deleted += 1
    }
    FeatureDiagnostics.record(.storage, .completed)
    return deleted
  }

  static func scan() async throws -> StorageUsageSnapshot {
    let operationID = UUID().uuidString
    let started = Date()
    FeatureDiagnostics.record(.storage, .started, operationID: operationID)
    let worker = Task.detached(priority: .utility) {
      try Task.checkCancellation()
      let fm = FileManager.default
      let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      let installation = Bundle.main.bundleURL
      let group = AppGroup.containerURL
      var roots = [
        StorageUsageRoot(url: home, label: "App"),
        StorageUsageRoot(url: installation, label: "Application"),
      ]
      var routes = [
        StorageUsageRoute(url: installation, category: .appInstallation),
        StorageUsageRoute(url: ModelStorageManager.modelsRoot, category: .speechModels,
          modelNames: Dictionary(uniqueKeysWithValues: ModelVariant.allCases.map { ($0.rawValue, $0.displayName) })),
        StorageUsageRoute(url: LLMModelStorageManager.modelsRoot, category: .textModels,
          modelNames: Dictionary(uniqueKeysWithValues: LLMModelVariant.allCases.map { ($0.rawValue, $0.displayName) })),
        StorageUsageRoute(url: fm.temporaryDirectory, category: .cache),
        StorageUsageRoute(url: home.appendingPathComponent("Library/Preferences"), category: .settings),
      ]
      if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
        routes.append(StorageUsageRoute(url: caches, category: .cache))
      }
      for cache in [ModelStorageManager.persistentCoreMLCacheURL(), ModelStorageManager.compiledModelCacheURL()] {
        if let cache { routes.append(StorageUsageRoute(url: cache, category: .compiledModels)) }
      }
      if let group {
        roots.append(StorageUsageRoot(url: group, label: "Shared"))
        // These are the existing owners' persisted folders; inspecting storage
        // must not invoke their directory-creating or transcript-loading APIs.
        let sharedRoutes: [(String, StorageUsageCategory)] = [
          ("audio", .voiceNotes), ("transcription-outbox-v1", .voiceNotes),
          ("meetings", .meetings), ("conversation-draft", .conversationDraft),
          ("Library/Preferences", .settings), ("Library/Caches", .cache),
          ("feature-diagnostics-v1.jsonl", .diagnostics),
        ]
        for (path, category) in sharedRoutes {
          routes.append(StorageUsageRoute(url: group.appendingPathComponent(path), category: category))
        }
      }
      if let history = HistoryStore.shared.rawHistoryIndexURL {
        routes.append(StorageUsageRoute(url: history, category: .voiceNotes))
      }
      let inventory = try StorageUsageScanner.scan(roots: roots, routes: routes)
      guard inventory.scannedRootCount > 0 else { throw CocoaError(.fileReadNoPermission) }
      let capacity = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
      let device: DeviceStorageUsage?
      if let total = capacity?.volumeTotalCapacity, let available = capacity?.volumeAvailableCapacity {
        device = DeviceStorageUsage(totalBytes: Int64(total), availableBytes: Int64(available))
      } else {
        device = nil
      }
      try Task.checkCancellation()
      return StorageUsageSnapshot(device: device, inventory: inventory, sharedStorageUnavailable: group == nil)
    }
    do {
      let snapshot = try await withTaskCancellationHandler {
        try await worker.value
      } onCancel: {
        worker.cancel()
      }
      try Task.checkCancellation()
      let duration = max(0, Int(Date().timeIntervalSince(started) * 1_000))
      // Capacity, file sizes, names and paths stay on-device. Diagnostics record
      // lifecycle and partial-result status only, using the shared bounded store.
      if snapshot.isIncomplete || snapshot.inventory.usedSizeFallback {
        FeatureDiagnostics.record(.storage, .fallback, operationID: operationID)
      }
      if snapshot.device == nil {
        FeatureDiagnostics.record(.storage, .unavailable, operationID: operationID)
      }
      if duration > 2_000 {
        FeatureDiagnostics.record(.storage, .slow, durationMs: duration, operationID: operationID)
      }
      FeatureDiagnostics.record(.storage, .completed, durationMs: duration, operationID: operationID)
      return snapshot
    } catch is CancellationError {
      FeatureDiagnostics.record(.storage, .cancelled, operationID: operationID)
      throw CancellationError()
    } catch {
      FeatureDiagnostics.record(.storage, .failed, failureReason: .destinationUnavailable,
        operationID: operationID)
      throw error
    }
  }
}
