import AVFoundation
import Combine
import Foundation

/// Plays a meeting as one timeline while keeping its stored 15-minute parts
/// separate. Only one audio file is opened at a time.
@MainActor
final class MeetingAudioPlayback: ObservableObject {
  @Published private(set) var recordID: UUID?
  @Published private(set) var isPlaying = false
  @Published private(set) var position: TimeInterval = 0
  @Published private(set) var duration: TimeInterval = 0

  private var current: MeetingRecord?
  private var player: AVAudioPlayer?
  private var partIndex = 0
  private var partStart: TimeInterval = 0
  private var tick: Timer?

  func toggle(_ record: MeetingRecord) {
    if self.recordID != record.id {
      _ = self.open(record, at: 0, autoplay: true)
      return
    }
    if self.isPlaying {
      self.player?.pause()
      self.isPlaying = false
    } else {
      if self.position >= self.duration - 0.1 {
        _ = self.open(record, at: 0, autoplay: true)
      } else {
        self.isPlaying = self.player?.play() ?? false
        self.startTimer()
      }
    }
  }

  func seek(to seconds: TimeInterval, in record: MeetingRecord) {
    _ = self.open(record, at: seconds, autoplay: self.isPlaying)
  }

  func skip(_ delta: TimeInterval, in record: MeetingRecord) {
    self.seek(to: max(0, min(record.totalDuration, self.position + delta)), in: record)
  }

  func stop() {
    self.tick?.invalidate()
    self.tick = nil
    self.player?.stop()
    self.player = nil
    self.current = nil
    self.recordID = nil
    self.isPlaying = false
    self.position = 0
    self.duration = 0
  }

  private func open(
    _ record: MeetingRecord, at offset: TimeInterval, autoplay: Bool
  ) -> Bool {
    let parts = record.parts.sorted { $0.number < $1.number }
    guard !parts.isEmpty else {
      self.stop()
      return false
    }
    let total = record.totalDuration
    let target = min(max(0, offset), max(0, total - 0.01))
    var begin: TimeInterval = 0
    var selectedIndex = 0
    for (index, part) in parts.enumerated() {
      if target < begin + part.duration || index == parts.count - 1 {
        selectedIndex = index
        break
      }
      begin += part.duration
    }
    let selected = parts[selectedIndex]
    guard let url = self.audioURL(for: selected, record: record),
          let audio = try? AVAudioPlayer(contentsOf: url) else {
      self.isPlaying = false
      return false
    }
    self.player?.stop()
    audio.prepareToPlay()
    audio.currentTime = min(audio.duration, max(0, target - begin))
    self.player = audio
    self.current = record
    self.recordID = record.id
    self.partIndex = selectedIndex
    self.partStart = begin
    self.position = target
    self.duration = total
    if autoplay {
      try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try? AVAudioSession.sharedInstance().setActive(true)
    }
    self.isPlaying = autoplay ? audio.play() : false
    self.startTimer()
    return true
  }

  private func audioURL(for part: MeetingAudioPart, record: MeetingRecord) -> URL? {
    let name = part.fileName
    guard !name.isEmpty, !name.contains("/"), !name.contains("\\"),
          name != ".", name != "..", name.hasSuffix(".caf"),
          let folder = MeetingRecordingCoordinator.shared.meetingFolder(for: record)
    else { return nil }
    return folder.appendingPathComponent("audio", isDirectory: true)
      .appendingPathComponent(name, isDirectory: false)
  }

  private func startTimer() {
    self.tick?.invalidate()
    guard self.isPlaying else { self.tick = nil; return }
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in self?.refresh() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.tick = timer
  }

  private func refresh() {
    guard let player = self.player, let record = self.current else { return }
    self.position = min(self.duration, self.partStart + player.currentTime)
    guard self.isPlaying, !player.isPlaying else { return }
    let parts = record.parts.sorted { $0.number < $1.number }
    if self.partIndex + 1 < parts.count {
      let next = self.partStart + parts[self.partIndex].duration
      _ = self.open(record, at: next, autoplay: true)
    } else {
      self.position = self.duration
      self.isPlaying = false
      self.tick?.invalidate()
      self.tick = nil
    }
  }
}
