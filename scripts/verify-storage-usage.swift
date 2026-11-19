import Foundation

@main
enum VerifyStorageUsage {
  static func main() throws {
    let fm = FileManager.default
    let fixture = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: fixture, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: fixture) }
    let app = fixture.appendingPathComponent("App", isDirectory: true)
    let installation = fixture.appendingPathComponent("Sayboard.app", isDirectory: true)
    let group = fixture.appendingPathComponent("Shared", isDirectory: true)
    let models = app.appendingPathComponent("Models", isDirectory: true)
    let cache = app.appendingPathComponent("CoreMLCache", isDirectory: true)
    var originalFiles = [URL]()

    func write(_ root: URL, _ path: String, _ size: Int) throws -> URL {
      let file = root.appendingPathComponent(path)
      try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(repeating: 37, count: size).write(to: file)
      originalFiles.append(file)
      return file
    }

    _ = try write(installation, "Sayboard", 24_576)
    _ = try write(installation, "PlugIns/Keyboard.appex/Keyboard", 16_384)
    _ = try write(installation, "Frameworks/Engine.framework/Engine", 8_192)
    let weights = try write(models, "known/weights.bin", 16_384)
    _ = try write(models, "known/.download-partial", 4_096)
    _ = try write(models, "incomplete/model.partial", 8_192)
    _ = try write(app, "LLMModels/text/model.gguf", 12_288)
    _ = try write(cache, "compiled.bin", 6_144)
    _ = try write(app, "Models-old/unrelated.bin", 1_024)
    _ = try write(group, "audio/note.caf", 5_120)
    _ = try write(group, "history.json", 2_048)
    _ = try write(group, "meetings/one/audio.caf", 7_168)
    _ = try write(group, "conversation-draft/turns.json", 1_024)
    let denied = try write(group, "denied.bin", 1_024)
    for index in 0..<(StorageUsageScanner.detailLimit + 5) {
      _ = try write(app, "tmp/\(index).bin", (index + 1) * 4_096)
    }
    let outside = fixture.appendingPathComponent("outside", isDirectory: true)
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data(repeating: 99, count: 100_000).write(to: outside.appendingPathComponent("external.bin"))
    try fm.createSymbolicLink(at: app.appendingPathComponent("cache-link"), withDestinationURL: cache)
    try fm.createSymbolicLink(at: app.appendingPathComponent("outside-link"), withDestinationURL: outside)
    try fm.createSymbolicLink(at: fixture.appendingPathComponent("root-link"), withDestinationURL: outside)
    let hardlink = models.appendingPathComponent("known/weights-hardlink.bin")
    try fm.linkItem(at: weights, to: hardlink)
    let sameContents = try write(app, "same-content.bin", 16_384)
    let weightIdentity = try identity(weights)
    let hardlinkIdentity = try identity(hardlink)
    let copiedIdentity = try identity(sameContents)
    require(weightIdentity == hardlinkIdentity, "Hard-link fixture must refer to the same device/inode")
    require(weightIdentity != copiedIdentity, "Equal-content files must have different device/inode identities")

    let roots = [StorageUsageRoot(url: app, label: "App"), StorageUsageRoot(url: group, label: "Shared"),
      StorageUsageRoot(url: installation, label: "Application")]
    let routes = [
      StorageUsageRoute(url: installation, category: .appInstallation),
      StorageUsageRoute(url: models, category: .speechModels, modelNames: ["known": "Known Model"]),
      StorageUsageRoute(url: app.appendingPathComponent("LLMModels"), category: .textModels, modelNames: [:]),
      StorageUsageRoute(url: cache, category: .compiledModels),
      StorageUsageRoute(url: app.appendingPathComponent("tmp"), category: .cache),
      StorageUsageRoute(url: group.appendingPathComponent("audio"), category: .voiceNotes),
      StorageUsageRoute(url: group.appendingPathComponent("history.json"), category: .voiceNotes),
      StorageUsageRoute(url: group.appendingPathComponent("meetings"), category: .meetings),
      StorageUsageRoute(url: group.appendingPathComponent("conversation-draft"), category: .conversationDraft),
    ]
    let inventory = try StorageUsageScanner.scan(roots: roots, routes: routes)
    let expectedBytes = try originalFiles.reduce(Int64(0)) { try $0 + bytes($1) }
    if inventory.totalBytes != expectedBytes || inventory.fileCount != originalFiles.count {
      // All names and numbers here belong to this synthetic temporary fixture.
      diagnostic("Expected bytes=\(expectedBytes), files=\(originalFiles.count); " +
        "actual bytes=\(inventory.totalBytes), files=\(inventory.fileCount), " +
        "unreadable=\(inventory.unreadableItemCount), roots=\(inventory.scannedRootCount)")
      for item in inventory.items {
        diagnostic("\(item.id): bytes=\(item.bytes), files=\(item.fileCount)")
        for file in item.files { diagnostic("  \(file.name): \(file.bytes)") }
      }
    }
    let temporaryFileCount = inventory.items.first { $0.category == .cache }?.fileCount ?? 0
    let textModelFileCount = inventory.items.first { $0.category == .textModels }?.fileCount ?? 0
    require(temporaryFileCount == StorageUsageScanner.detailLimit + 5,
      "Skipping symlinks must preserve every temporary sibling file: expected \(StorageUsageScanner.detailLimit + 5), actual \(temporaryFileCount)")
    require(textModelFileCount == 1,
      "Skipping symlinks must preserve the text-model sibling directory: expected 1 file, actual \(textModelFileCount)")
    require(inventory.totalBytes == expectedBytes,
      "Disk total must count each real file exactly once: expected \(expectedBytes), actual \(inventory.totalBytes)")
    require(inventory.fileCount == originalFiles.count,
      "Symlinks and hard links must not add files: expected \(originalFiles.count), actual \(inventory.fileCount)")
    require(inventory.unreadableItemCount == 0 && inventory.scannedRootCount == 3, "Readable roots must scan completely")
    require(inventory.items.first { $0.category == .appInstallation }?.fileCount == 3,
      "App installation must include the executable, keyboard extension and frameworks")
    require(inventory.items.contains { $0.modelName == "Known Model" }, "Known model names must be retained")
    require(inventory.items.contains { $0.modelName == "incomplete" && $0.bytes > 0 }, "Partial downloads must occupy space")
    require(inventory.items.first { $0.modelName == "Known Model" }?.fileCount == 2, "Hidden partial files must be included")
    require(inventory.items.contains { $0.category == .textModels }, "Text models must be listed")
    require(inventory.items.contains { $0.category == .other && $0.files.contains { $0.name.contains("Models-old") } },
      "Sibling folder prefixes must not match a model root")
    require(inventory.items.contains { $0.category == .meetings } && inventory.items.contains { $0.category == .conversationDraft },
      "Existing meeting and draft storage must be classified")
    require(inventory.items.allSatisfy { $0.files.count <= StorageUsageScanner.detailLimit }, "Retained file detail must be bounded")
    let temporary = inventory.items.first { $0.category == .cache }!
    require(temporary.fileCount == StorageUsageScanner.detailLimit + 5, "Bounded details must not truncate totals")
    require((temporary.files.first?.bytes ?? 0) >= (temporary.files.last?.bytes ?? 0), "Largest files must appear first")

    let overlapping = try StorageUsageScanner.scan(roots: roots + [
      StorageUsageRoot(url: app, label: "Again"), StorageUsageRoot(url: models, label: "Nested"),
      StorageUsageRoot(url: installation.appendingPathComponent("PlugIns"), label: "Extension"),
      StorageUsageRoot(url: fixture.appendingPathComponent("root-link"), label: "Link"),
    ], routes: routes)
    require(overlapping.totalBytes == inventory.totalBytes && overlapping.fileCount == inventory.fileCount,
      "Overlapping roots and root symlinks must not add usage")

    let partial = try StorageUsageScanner.scan(roots: roots, routes: routes, readValues: { url in
      if url.lastPathComponent == denied.lastPathComponent { throw CocoaError(.fileReadNoPermission) }
      var fresh = url
      fresh.removeAllCachedResourceValues()
      return try fresh.resourceValues(forKeys: StorageUsageScanner.resourceKeys)
    })
    require(partial.unreadableItemCount == 1, "A failed metadata read must mark the result incomplete")
    let deniedBytes = try bytes(denied)
    require(partial.totalBytes == expectedBytes - deniedBytes, "A failed read must preserve all other totals")

    var checks = 0
    do {
      _ = try StorageUsageScanner.scan(roots: roots, routes: routes, isCancelled: {
        checks += 1
        return checks > 8
      })
      fatalError("Cancellation must terminate the scan")
    } catch is CancellationError { }
    let recovered = try StorageUsageScanner.scan(roots: roots, routes: routes)
    require(recovered.totalBytes == expectedBytes, "Cancellation must not alter stored data or prevent a later scan")
    let empty = fixture.appendingPathComponent("Empty", isDirectory: true)
    try fm.createDirectory(at: empty, withIntermediateDirectories: true)
    let emptyResult = try StorageUsageScanner.scan(roots: [StorageUsageRoot(url: empty, label: "Empty")], routes: [])
    require(emptyResult.totalBytes == 0 && emptyResult.items.isEmpty && emptyResult.scannedRootCount == 1,
      "An empty readable folder must differ from an unavailable root")
    let missing = try StorageUsageScanner.scan(roots: [StorageUsageRoot(url: empty.appendingPathComponent("missing"), label: "Missing")], routes: [])
    require(missing.unreadableItemCount == 1 && missing.scannedRootCount == 0, "Missing roots must not appear as a complete empty scan")

    let device = DeviceStorageUsage(totalBytes: 64_000_000_000, availableBytes: 16_000_000_000)!
    require(device.usedBytes == 48_000_000_000 && device.usedFraction == 0.75, "Percentage denominator must be device capacity")
    require(DeviceStorageUsage(totalBytes: 0, availableBytes: 0) == nil, "Zero capacity must be unavailable")
    require(DeviceStorageUsage(totalBytes: 1, availableBytes: 2) == nil, "Inconsistent capacity must be unavailable")
    require(DeviceStorageUsage(totalBytes: 1, availableBytes: -1) == nil, "Negative capacity must be unavailable")
    require(DeviceStorageUsage(totalBytes: 100, availableBytes: 100)?.usedFraction == 0, "Empty device must show zero percent used")
    require(DeviceStorageUsage(totalBytes: 100, availableBytes: 0)?.usedFraction == 1, "Full device must show 100 percent used")
    print("Storage usage fixtures passed")
  }

  private static func bytes(_ url: URL) throws -> Int64 {
    var fresh = url
    fresh.removeAllCachedResourceValues()
    let values = try fresh.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
    return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
  }

  private static func identity(_ url: URL) throws -> [UInt64] {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    guard let device = attributes[.systemNumber] as? NSNumber,
          let inode = attributes[.systemFileNumber] as? NSNumber else {
      throw CocoaError(.fileReadUnknown)
    }
    return [device.uint64Value, inode.uint64Value]
  }

  private static func diagnostic(_ message: String) {
    try? FileHandle.standardError.write(contentsOf: Data((message + "\n").utf8))
  }

  private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
  }
}
