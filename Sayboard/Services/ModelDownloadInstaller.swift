import Foundation
import ZIPFoundation

enum ModelDownloadInstaller {
  static func install(source: URL, destination: URL, ggufFileName: String?) throws {
    let fm = FileManager.default
    let staging = fm.temporaryDirectory
      .appendingPathComponent("model-install-" + UUID().uuidString, isDirectory: true)
    defer {
      try? fm.removeItem(at: staging)
      try? fm.removeItem(at: source)
    }
    try fm.createDirectory(at: staging, withIntermediateDirectories: true)
    if let name = ggufFileName {
      guard !name.isEmpty, name == (name as NSString).lastPathComponent,
            !name.contains("\\"), name.hasSuffix(".gguf") else {
        throw CocoaError(.fileReadCorruptFile)
      }
      let handle = try FileHandle(forReadingFrom: source)
      defer { try? handle.close() }
      guard try handle.read(upToCount: 4) == Data("GGUF".utf8) else {
        throw CocoaError(.fileReadCorruptFile)
      }
      try fm.moveItem(at: source, to: staging.appendingPathComponent(name))
    } else {
      try fm.unzipItem(at: source, to: staging)
    }
    try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    if fm.fileExists(atPath: destination.path) {
      _ = try fm.replaceItemAt(destination, withItemAt: staging)
    } else {
      try fm.moveItem(at: staging, to: destination)
    }
    var protectedURL = destination
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? protectedURL.setResourceValues(values)
  }
}
