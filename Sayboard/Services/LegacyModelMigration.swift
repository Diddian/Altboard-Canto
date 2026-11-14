import Foundation

private let migrationKey = "hasCompletedR2Migration"
private let legacyWhisperKitPathPrefix = "whisperKitModelPath_"
private let legacyParakeetDownloadedPrefix = "parakeetModelDownloaded_"

enum LegacyModelMigration {

  static func runIfNeeded() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: migrationKey) else { return }

    do { try ModelStorageManager.ensureRootExists() }
    catch {
      FeatureDiagnostics.record(.speechModel, .failed)
      return
    }
    let whisperComplete = self.migrateWhisperKitModels(defaults: defaults)
    let parakeetComplete = self.migrateParakeetModels(defaults: defaults)
    guard whisperComplete && parakeetComplete else {
      FeatureDiagnostics.record(.speechModel, .fallback)
      return
    }
    self.cleanupLegacyCaches()
    defaults.set(true, forKey: migrationKey)
  }

  @discardableResult
  private static func migrateWhisperKitModels(defaults: UserDefaults) -> Bool {
    let fm = FileManager.default
    var completed = true
    for variant in ModelVariant.allCases where variant.engine == .whisperKit {
      let key = "\(legacyWhisperKitPathPrefix)\(variant.rawValue)"
      guard let oldPath = defaults.string(forKey: key), !oldPath.isEmpty else { continue }
      if ModelStorageManager.isDownloaded(variant) {
        defaults.removeObject(forKey: key)
        continue
      }

      let oldURL = URL(fileURLWithPath: oldPath)
      guard fm.fileExists(atPath: oldURL.path) else {
        completed = false
        continue
      }
      let newDir = ModelStorageManager.directory(for: variant)
      do {
        try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        let destination = newDir.appendingPathComponent(oldURL.lastPathComponent)
        if !fm.fileExists(atPath: destination.path) {
          try fm.moveItem(at: oldURL, to: destination)
        }
        if ModelStorageManager.isDownloaded(variant) {
          defaults.removeObject(forKey: key)
        } else {
          completed = false
        }
      } catch {
        completed = false
      }
    }
    return completed
  }

  @discardableResult
  private static func migrateParakeetModels(defaults: UserDefaults) -> Bool {
    let fm = FileManager.default
    var completed = true
    for variant in ModelVariant.allCases where variant.engine == .parakeet {
      let key = "\(legacyParakeetDownloadedPrefix)\(variant.rawValue)"
      guard defaults.bool(forKey: key) else { continue }
      if ModelStorageManager.isDownloaded(variant) {
        defaults.removeObject(forKey: key)
        continue
      }
      guard let repoFolder = variant.parakeetRepoFolderName,
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      else {
        completed = false
        continue
      }
      let oldDir = appSupport
        .appendingPathComponent("FluidAudio")
        .appendingPathComponent("Models")
        .appendingPathComponent(repoFolder)
      guard fm.fileExists(atPath: oldDir.path) else {
        completed = false
        continue
      }
      let newDir = ModelStorageManager.directory(for: variant)
      do {
        try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
        let destination = newDir.appendingPathComponent(repoFolder)
        if !fm.fileExists(atPath: destination.path) {
          try fm.moveItem(at: oldDir, to: destination)
        }
        if ModelStorageManager.isDownloaded(variant) {
          defaults.removeObject(forKey: key)
        } else {
          completed = false
        }
      } catch {
        completed = false
      }
    }
    return completed
  }

  private static func cleanupLegacyCaches() {
    let fm = FileManager.default

    if let appSupportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
      let hfCacheDir = appSupportDir.appendingPathComponent("huggingface")
      if fm.fileExists(atPath: hfCacheDir.path) {
        try? fm.removeItem(at: hfCacheDir)
      }

      let fluidDir = appSupportDir.appendingPathComponent("FluidAudio")
      if fm.fileExists(atPath: fluidDir.path) {
        let contents = (try? fm.contentsOfDirectory(atPath: fluidDir.path)) ?? []
        if contents.isEmpty {
          try? fm.removeItem(at: fluidDir)
        }
      }
    }

    if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
      let fluidCacheDir = cachesDir.appendingPathComponent("FluidAudio")
      if fm.fileExists(atPath: fluidCacheDir.path) {
        try? fm.removeItem(at: fluidCacheDir)
      }
    }
  }
}
