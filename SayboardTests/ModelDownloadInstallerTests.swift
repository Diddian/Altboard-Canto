import Foundation
import Testing
import ZIPFoundation
@testable import Sayboard

@Suite("Model download installation")
struct ModelDownloadInstallerTests {
  @Test func installsVerifiedRawGGUF() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let source = root.appendingPathComponent("download")
    let target = root.appendingPathComponent("model")
    let data = Data("GGUFfixture".utf8)
    try data.write(to: source)
    try ModelDownloadInstaller.install(source: source, destination: target, ggufFileName: "model.gguf")
    #expect(try Data(contentsOf: target.appendingPathComponent("model.gguf")) == data)
    #expect(!FileManager.default.fileExists(atPath: source.path))
  }

  @Test func corruptGGUFDoesNotReplaceAnInstalledModel() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("model")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let existing = target.appendingPathComponent("model.gguf")
    try Data("GGUForiginal".utf8).write(to: existing)
    let source = root.appendingPathComponent("download")
    try Data("HTMLnotamodel".utf8).write(to: source)
    #expect(throws: (any Error).self) {
      try ModelDownloadInstaller.install(source: source, destination: target, ggufFileName: "model.gguf")
    }
    #expect(try Data(contentsOf: existing) == Data("GGUForiginal".utf8))
  }

  @Test func keepsZIPDownloadsWorking() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let content = root.appendingPathComponent("source")
    try FileManager.default.createDirectory(at: content, withIntermediateDirectories: true)
    try Data("model fixture".utf8).write(to: content.appendingPathComponent("weights"))
    let zip = root.appendingPathComponent("download.zip")
    try FileManager.default.zipItem(at: content, to: zip, shouldKeepParent: false)
    let target = root.appendingPathComponent("installed")
    try ModelDownloadInstaller.install(source: zip, destination: target, ggufFileName: nil)
    #expect(try Data(contentsOf: target.appendingPathComponent("weights")) == Data("model fixture".utf8))
  }
  @Test func traversalNameKeepsPreviouslyInstalledModel() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("model")
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    let existing = target.appendingPathComponent("model.gguf")
    let content = Data("GGUForiginal".utf8)
    try content.write(to: existing)
    let source = root.appendingPathComponent("download")
    try Data("GGUFchanged".utf8).write(to: source)
    #expect(throws: (any Error).self) {
      try ModelDownloadInstaller.install(source: source, destination: target,
                                         ggufFileName: "../escaped.gguf")
    }
    #expect(try Data(contentsOf: existing) == content)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.gguf").path))
  }

}
