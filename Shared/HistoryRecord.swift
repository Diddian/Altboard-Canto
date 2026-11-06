import Foundation

struct HistoryRecord: Codable, Identifiable, Sendable {

  init(
    id: UUID,
    date: Date,
    duration: TimeInterval,
    transcription: String,
    audioFileName: String,
    waveformSamples: [Float] = [],
    originalASR: String? = nil,
    userCorrection: String? = nil,
  ) {
    self.id = id
    self.date = date
    self.duration = duration
    self.transcription = transcription
    self.audioFileName = audioFileName
    self.waveformSamples = waveformSamples
    self.originalASR = originalASR
    self.userCorrection = userCorrection
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.id = try container.decode(UUID.self, forKey: .id)
    self.date = try container.decode(Date.self, forKey: .date)
    self.duration = try container.decode(TimeInterval.self, forKey: .duration)
    self.transcription = try container.decode(String.self, forKey: .transcription)
    self.audioFileName = try container.decode(String.self, forKey: .audioFileName)
    self.waveformSamples = (try? container.decode([Float].self, forKey: .waveformSamples)) ?? []
    self.originalASR = try container.decodeIfPresent(String.self, forKey: .originalASR)
    self.userCorrection = try container.decodeIfPresent(String.self, forKey: .userCorrection)
  }

  let id: UUID
  let date: Date
  let duration: TimeInterval
  let transcription: String
  let audioFileName: String
  let waveformSamples: [Float]
  /// Unstyled, uncorrected speech recognizer result (new records only).
  let originalASR: String?
  /// Verified spoken words entered explicitly by the user in History.
  let userCorrection: String?

  var displayedTranscription: String {
    self.userCorrection ?? self.transcription
  }

  func withCorrection(_ correction: String?) -> HistoryRecord {
    HistoryRecord(
      id: self.id, date: self.date, duration: self.duration,
      transcription: self.transcription, audioFileName: self.audioFileName,
      waveformSamples: self.waveformSamples,
      originalASR: self.originalASR, userCorrection: correction
    )
  }
}

