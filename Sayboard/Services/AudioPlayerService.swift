@preconcurrency import AVFoundation
import SwiftUI

@MainActor
final class AudioPlayerService: ObservableObject {

  @Published var isPlaying = false
  @Published var duration: TimeInterval = 0
  @Published var currentFileURL: URL?

  var playbackTime: TimeInterval {
    self.player?.currentTime ?? 0
  }

  func play(url: URL) {
    if self.currentFileURL == url, let player {
      guard BackgroundAudioSession.configurePlayback(owner: self.playbackOwner, stop: { [weak self] in
        self?.stop()
      }) else { return }
      self.isPlaying = player.play()
      if !self.isPlaying { self.stop() }
      return
    }

    self.stop()
    guard BackgroundAudioSession.configurePlayback(owner: self.playbackOwner, stop: { [weak self] in
      self?.stop()
    }) else { return }

    do {
      let newPlayer = try AVAudioPlayer(contentsOf: url)
      newPlayer.delegate = self.delegateAdapter
      newPlayer.prepareToPlay()
      guard newPlayer.play() else {
        BackgroundAudioSession.releasePlayback(owner: self.playbackOwner)
        return
      }
      self.player = newPlayer
      self.currentFileURL = url
      self.duration = newPlayer.duration
      self.isPlaying = true
    } catch {
      BackgroundAudioSession.releasePlayback(owner: self.playbackOwner)
      self.isPlaying = false
    }
  }

  func pause() {
    self.player?.pause()
    self.isPlaying = false
    BackgroundAudioSession.releasePlayback(owner: self.playbackOwner)
  }

  func stop() {
    BackgroundAudioSession.releasePlayback(owner: self.playbackOwner)
    self.player?.stop()
    self.player = nil
    self.isPlaying = false
    self.duration = 0
    self.currentFileURL = nil
  }

  func seek(to time: TimeInterval) {
    self.player?.currentTime = time
    self.objectWillChange.send()
  }

  func togglePlayback(url: URL) {
    if self.currentFileURL == url, self.isPlaying {
      self.pause()
    } else {
      self.play(url: url)
    }
  }

  private let playbackOwner = UUID()
  private var player: AVAudioPlayer?
  private lazy var delegateAdapter = PlayerDelegateAdapter { [weak self] completedPlayer in
    self?.handlePlaybackFinished(completedPlayer)
  }

  private func handlePlaybackFinished(_ completedPlayer: ObjectIdentifier) {
    guard let player = self.player, ObjectIdentifier(player) == completedPlayer else { return }
    BackgroundAudioSession.releasePlayback(owner: self.playbackOwner)
    self.player = nil
    self.isPlaying = false
    self.duration = 0
    self.currentFileURL = nil
  }
}

private final class PlayerDelegateAdapter: NSObject, AVAudioPlayerDelegate {

  init(onFinish: @escaping @MainActor (ObjectIdentifier) -> Void) {
    self.onFinish = onFinish
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully _: Bool) {
    let callback = self.onFinish
    let completedPlayer = ObjectIdentifier(player)
    Task { @MainActor in
      callback(completedPlayer)
    }
  }

  private let onFinish: @MainActor (ObjectIdentifier) -> Void
}

