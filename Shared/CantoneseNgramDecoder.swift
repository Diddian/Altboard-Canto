import Foundation

/// A verified lexicon reading, never an ungrounded phonetic substitution.
struct CantoneseNgramPiece: Equatable {
  let text: String
  let romanization: String
}

/// Bounded, offline beam search. All lookup and frequency state lives only
/// for the current candidate request; no host text or typing history is stored.
enum CantoneseNgramDecoder {
  private struct Route {
    var text: String
    var romanization: String
    var chunks: Int
    var score: Double
  }

  static func decode(
    _ spelling: String,
    limit: Int = 8,
    choices: (String) -> [CantoneseNgramPiece],
    frequency: (String) -> Int,
    wordFrequency: (String) -> Int
  ) -> [CantoneseNgramPiece] {
    let source = spelling.lowercased()
    guard (4...48).contains(source.count),
          source.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
    let characters = Array(source)
    let width = characters.count
    let beamWidth = 7
    let maxChunks = 7
    var beams = Array(repeating: [Route](), count: width + 1)
    beams[0] = [Route(text: "", romanization: "", chunks: 0, score: 0)]
    var probes = 0
    var cachedChoices = [String: [CantoneseNgramPiece]]()
    var cachedFrequencies = [String: Double]()
    var cachedWords = [String: Double]()

    func gramScore(_ gram: String) -> Double {
      if let cached = cachedFrequencies[gram] { return cached }
      let value = log1p(Double(max(0, frequency(gram))))
      cachedFrequencies[gram] = value
      return value
    }

    func wordScore(_ word: String) -> Double {
      if let cached = cachedWords[word] { return cached }
      let value = log1p(Double(max(0, wordFrequency(word))))
      cachedWords[word] = value
      return value
    }

    func additionScore(_ prior: String, _ next: String) -> Double {
      var last = Array(prior.suffix(2))
      var score = 0.0
      for character in next {
        let current = String(character)
        score += 0.06 * gramScore(current)
        if let previous = last.last {
          score += 1.10 * gramScore(String(previous) + current)
        }
        if last.count == 2 {
          score += 1.45 * gramScore(String(last[0]) + String(last[1]) + current)
        }
        last.append(character)
        if last.count > 2 { last.removeFirst() }
      }
      return score
    }

    func better(_ lhs: Route, _ rhs: Route) -> Bool {
      if lhs.score != rhs.score { return lhs.score > rhs.score }
      if lhs.chunks != rhs.chunks { return lhs.chunks < rhs.chunks }
      if lhs.text != rhs.text { return lhs.text < rhs.text }
      return lhs.romanization < rhs.romanization
    }

    for start in 0..<width where !beams[start].isEmpty {
      let upper = min(width, start + 14)
      for end in (start + 1)...upper {
        let length = end - start
        if length == 1 && characters[start] != "m" { continue }
        if probes >= 88 { break }
        let code = String(characters[start..<end])
        let entries: [CantoneseNgramPiece]
        if let cached = cachedChoices[code] {
          entries = cached
        } else {
          probes += 1
          entries = Array(choices(code).prefix(5))
          cachedChoices[code] = entries
        }
        guard !entries.isEmpty else { continue }
        for route in beams[start] where route.chunks < maxChunks {
          for piece in entries where (1...5).contains(piece.text.count) {
            let extra = additionScore(route.text, piece.text)
              + 0.55 * wordScore(piece.text) - 1.7
            let newRoute = Route(
              text: route.text + piece.text,
              romanization: route.romanization.isEmpty
                ? piece.romanization : route.romanization + " " + piece.romanization,
              chunks: route.chunks + 1,
              score: route.score + extra
            )
            beams[end].append(newRoute)
          }
        }
        if beams[end].count > beamWidth {
          beams[end].sort(by: better)
          beams[end] = Array(beams[end].prefix(beamWidth))
        }
      }
    }

    var seen = Set<String>()
    return beams[width]
      .filter { $0.chunks >= 2 && $0.text.count >= 2 }
      .sorted(by: better)
      .compactMap { route in
        guard seen.insert(route.text).inserted else { return nil }
        return CantoneseNgramPiece(text: route.text, romanization: route.romanization)
      }
      .prefix(max(1, min(16, limit)))
      .map { $0 }
  }
}
