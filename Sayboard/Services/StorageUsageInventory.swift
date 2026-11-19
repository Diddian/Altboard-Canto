import Foundation

enum StorageUsageCategory: String, CaseIterable, Identifiable, Sendable {
  case appInstallation, speechModels, textModels, compiledModels, voiceNotes, meetings, conversationDraft
  case cache, settings, diagnostics, other

  var id: String { self.rawValue }

  var titleKey: String {
    switch self {
    case .appInstallation: "App Installation"
    case .speechModels: "Speech Models"
    case .textModels: "AI Text Models"
    case .compiledModels: "Compiled Model Cache"
    case .voiceNotes: "Voice Notes"
    case .meetings: "Meetings"
    case .conversationDraft: "Conversation Draft"
    case .cache: "Caches & Temporary Files"
    case .settings: "Settings & Learned Vocabulary"
    case .diagnostics: "Diagnostics"
    case .other: "Other App Files"
    }
  }
}

struct DeviceStorageUsage: Sendable {
  let totalBytes: Int64
  let availableBytes: Int64

  init?(totalBytes: Int64, availableBytes: Int64) {
    guard totalBytes > 0, availableBytes >= 0, availableBytes <= totalBytes else { return nil }
    self.totalBytes = totalBytes
    self.availableBytes = availableBytes
  }

  var usedBytes: Int64 { self.totalBytes - self.availableBytes }
  var usedFraction: Double { Double(self.usedBytes) / Double(self.totalBytes) }
}

struct StorageUsageRoot: Sendable {
  let url: URL
  let label: String
}

struct StorageUsageRoute: Sendable {
  let url: URL
  let category: StorageUsageCategory
  // A non-nil catalog groups the first directory under this root as a model.
  // Unknown and incomplete model folders still appear using their folder name.
  var modelNames: [String: String]? = nil
}

struct StorageUsageFile: Identifiable, Sendable {
  let id: String
  let name: String
  let bytes: Int64
}

struct StorageUsageItem: Identifiable, Sendable {
  let id: String
  let category: StorageUsageCategory
  let modelName: String?
  var bytes: Int64 = 0
  var fileCount = 0
  var files: [StorageUsageFile] = []
}

struct StorageUsageInventory: Sendable {
  let items: [StorageUsageItem]
  let unreadableItemCount: Int
  let scannedRootCount: Int
  let usedSizeFallback: Bool

  var totalBytes: Int64 { self.items.reduce(0) { $0 + $1.bytes } }
  var fileCount: Int { self.items.reduce(0) { $0 + $1.fileCount } }

  func bytes(for category: StorageUsageCategory) -> Int64 {
    self.items.filter { $0.category == category }.reduce(0) { $0 + $1.bytes }
  }
}

/// Reads filesystem metadata only. Call from a utility worker, never the main actor.
/// No file contents, absolute paths or inventory values leave this process.
enum StorageUsageScanner {
  static let detailLimit = 30
  static let resourceKeys: Set<URLResourceKey> = [
    .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
  ]

  static func scan(
    roots: [StorageUsageRoot], routes: [StorageUsageRoute],
    isCancelled: () -> Bool = { Task.isCancelled },
    readValues: (URL) throws -> URLResourceValues = {
      var url = $0
      url.removeAllCachedResourceValues()
      return try url.resourceValues(forKeys: StorageUsageScanner.resourceKeys)
    }
  ) throws -> StorageUsageInventory {
    let fm = FileManager.default
    var unreadable = 0
    var scannedRoots = 0
    var usedSizeFallback = false
    var items = [String: StorageUsageItem]()
    var visitedFiles = Set<FileIdentity>()
    var acceptedRoots = [StorageUsageRoot]()

    func checkCancellation() throws {
      if isCancelled() { throw CancellationError() }
    }

    // Resolve only trusted roots. Do not traverse symlinks found within a root.
    for root in roots {
      try checkCancellation()
      do {
        let values = try readValues(root.url)
        guard values.isSymbolicLink != true, values.isDirectory == true else { continue }
        acceptedRoots.append(StorageUsageRoot(
          url: root.url.resolvingSymlinksInPath().standardizedFileURL, label: root.label
        ))
      } catch { unreadable += 1 }
    }
    acceptedRoots.sort { $0.url.path.count < $1.url.path.count }
    var uniqueRoots = [StorageUsageRoot]()
    for root in acceptedRoots where !uniqueRoots.contains(where: { contains(root.url, in: $0.url) }) {
      uniqueRoots.append(root)
    }
    let canonicalRoutes = routes.map {
      StorageUsageRoute(url: $0.url.resolvingSymlinksInPath().standardizedFileURL,
        category: $0.category, modelNames: $0.modelNames)
    }.sorted { $0.url.path.count > $1.url.path.count }

    for root in uniqueRoots {
      try checkCancellation()
      guard let enumerator = fm.enumerator(
        at: root.url, includingPropertiesForKeys: nil,
        options: [], errorHandler: { _, _ in unreadable += 1; return true }
      ) else { unreadable += 1; continue }
      scannedRoots += 1
      for case let url as URL in enumerator {
        try checkCancellation()
        do {
          let values = try readValues(url)
          if values.isSymbolicLink == true {
            enumerator.skipDescendants()
            continue
          }
          guard values.isRegularFile == true else { continue }
          let path = url.standardizedFileURL.path
          // Numeric device/inode identity also works when Foundation's opaque
          // resource identifiers cannot be bridged to Swift Hashable values.
          // attributesOfItem reads symlink metadata without following the link.
          let attributes = try fm.attributesOfItem(atPath: path)
          guard attributes[.type] as? FileAttributeType == .typeRegular,
                let device = attributes[.systemNumber] as? NSNumber,
                let inode = attributes[.systemFileNumber] as? NSNumber else {
            unreadable += 1
            continue
          }
          let identity = FileIdentity(device: device.uint64Value, inode: inode.uint64Value)
          guard visitedFiles.insert(identity).inserted else {
            continue
          }
          let allocated = values.totalFileAllocatedSize ?? values.fileAllocatedSize
          guard let size = allocated ?? values.fileSize, size >= 0 else {
            unreadable += 1
            continue
          }
          if allocated == nil { usedSizeFallback = true }
          let route = canonicalRoutes.first { contains(url, in: $0.url) }
          let category = route?.category ?? .other
          var itemID = category.rawValue
          var modelName: String?
          var name = root.label + "/" + relativePath(url, to: root.url)
          if let route, let catalog = route.modelNames {
            let relative = relativePath(url, to: route.url)
            if let folder = relative.split(separator: "/").first.map(String.init) {
              itemID += "/" + folder
              modelName = catalog[folder] ?? folder
              name = relative
            }
          }
          var item = items[itemID] ?? StorageUsageItem(
            id: itemID, category: category, modelName: modelName
          )
          let bytes = Int64(size)
          item.bytes += bytes
          item.fileCount += 1
          let file = StorageUsageFile(id: path, name: name, bytes: bytes)
          if item.files.count < self.detailLimit || ordered(file, before: item.files[item.files.count - 1]) {
            item.files.append(file)
            item.files.sort { ordered($0, before: $1) }
            if item.files.count > self.detailLimit { item.files.removeLast() }
          }
          items[itemID] = item
        } catch { unreadable += 1 }
      }
    }
    try checkCancellation()
    return StorageUsageInventory(
      items: items.values.sorted { $0.bytes == $1.bytes ? $0.id < $1.id : $0.bytes > $1.bytes },
      unreadableItemCount: unreadable, scannedRootCount: scannedRoots,
      usedSizeFallback: usedSizeFallback
    )
  }

  private struct FileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
  }

  private static func contains(_ url: URL, in root: URL) -> Bool {
    let path = url.standardizedFileURL.path
    let rootPath = root.standardizedFileURL.path
    return path == rootPath || path.hasPrefix(rootPath + "/")
  }

  private static func relativePath(_ url: URL, to root: URL) -> String {
    String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
  }

  private static func ordered(_ lhs: StorageUsageFile, before rhs: StorageUsageFile) -> Bool {
    lhs.bytes == rhs.bytes ? lhs.name < rhs.name : lhs.bytes > rhs.bytes
  }
}
