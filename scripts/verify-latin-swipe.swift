import Foundation

func stroke(_ word: String, order: LetterKeyArrangement) -> [LatinSwipePoint] {
  let centers = LatinSwipeDecoder.centers(arrangement: order, fullWidth: 440)
  return word.lowercased().compactMap { centers[String($0)] }
}

@main
enum SwipeSmoke {
  static func main() {
    for order in [LetterKeyArrangement.qwerty, .qwertz] {
  let centers = LatinSwipeDecoder.centers(arrangement: order, fullWidth: 440)
  precondition(centers.count == 26)
  precondition(centers["q"]!.x < centers["w"]!.x)
  precondition(centers["a"]!.y > centers["q"]!.y)
  precondition(centers["z"]!.y != centers["a"]!.y || order == .qwertz)
  let samples = LatinSwipeDecoder.resample(stroke("hello", order: order))
  precondition(samples.count == LatinSwipeDecoder.sampleCount)
  let choices = LatinSwipeDecoder.rank(
    path: stroke("hello", order: order), arrangement: order,
    fullWidth: 440, words: ["help", "hello", "yellow", "home"])
  precondition(choices.first == "hello", "hello path should rank hello: \(choices)")
  let german = LatinSwipeDecoder.rank(
    path: stroke("danke", order: order), arrangement: order,
    fullWidth: 440, words: ["danach", "danke", "denken", "dann"])
  precondition(german.first == "danke", "danke path: \(german)")
}
for order in [LetterKeyArrangement.qwerty, .qwertz] {
  let path = stroke("to", order: order)
  let candidates = LatinSwipeDecoder.rank(
    path: path, arrangement: order,
    fullWidth: 440, words: ["to", "today", "too", "top"])
  precondition(candidates.first == "to", "two-letter 'to' must be swipable: \\(candidates)")
  let shortSession = LatinSwipeSession()
  shortSession.begin(path[0], arrangement: order, width: 440)
  shortSession.append(path[1], arrangement: order, width: 440)
  precondition(shortSession.isLikelyGlide, "short 'to' stroke should be recognized as glide")
}
precondition(LatinSwipeDecoder.rank(
  path: [LatinSwipePoint(x: 100, y: 20), LatinSwipePoint(x: 105, y: 20)],
  arrangement: .qwerty, fullWidth: 440, words: ["to"]).isEmpty)
// Regression: repeated letters and returning to a previously used key must
// preserve each geometric segment, rather than deduplicating visited keys.
for order in [LetterKeyArrangement.qwerty, .qwertz] {
  for word in ["become", "evermore"] {
    let path = stroke(word, order: order)
    let decoded = LatinSwipeDecoder.rank(
      path: path, arrangement: order, fullWidth: 440,
      words: ["hello", "world", word]
    )
    precondition(decoded.first == word, "revisited letters: \\(word) -> \\(decoded)")
  }
}
// Long, backtracking and crossing paths must not vanish solely due to length.
for order in [LetterKeyArrangement.qwerty, .qwertz] {
  for word in ["penetrate", "strange", "tight", "intervention"] {
    let ideal = stroke(word, order: order)
    let decoded = LatinSwipeDecoder.rank(
      path: ideal, arrangement: order, fullWidth: 440,
      words: ["world", "hello", "through", word]
    )
    precondition(decoded.first == word, "long swipe path \(word): \(decoded)")
  }
}
let bounded = LatinSwipeSession()
let longTrace = stroke("penetrate", order: .qwerty)
bounded.begin(longTrace[0], arrangement: .qwerty, width: 440)
for _ in 0..<20 {
  for point in longTrace.dropFirst() { bounded.append(point, arrangement: .qwerty, width: 440) }
}
precondition(bounded.points.count <= 384, "swipe points must remain bounded")
// Regression: frequent short and long swipes must decode on both layouts.
// Geometric success alone is not device acceptance; real paths follow QA.
for order in [LetterKeyArrangement.qwerty, .qwertz] {
  for word in ["you", "not", "actually", "penetrate", "strange", "tight"] {
    let choices = LatinSwipeDecoder.rank(
      path: stroke(word, order: order), arrangement: order,
      fullWidth: 440, words: ["hello", "keyboard", "never", word]
    )
    precondition(choices.first == word, "common swipe \(word): \(choices)")
  }
}
// A contraction is swiped by its letters; apostrophes are restored by lexicon.
for order in [LetterKeyArrangement.qwerty, .qwertz] {
  let contractions = LatinSwipeDecoder.rank(
    path: stroke("thats", order: order), arrangement: order,
    fullWidth: 440, words: ["thank", "that", "that's", "thanks"]
  )
  precondition(contractions.first == "that's", "apostrophe contraction: \(contractions)")
}
// Colloquial English and German are swipe targets without new network data.
for order in [LetterKeyArrangement.qwerty, .qwertz] {
  for word in ["wanna", "gonna", "gotta", "kinda", "thinner",
               "naja", "krass", "chillen", "digga"] {
    let matches = LatinSwipeDecoder.rank(
      path: stroke(word, order: order), arrangement: order,
      fullWidth: 440, words: ["hello", "keyboard", "tomorrow", word]
    )
    precondition(matches.first == word, "colloquial swipe \(word): \(matches)")
  }
}
\(marker)
precondition(LatinSwipeDecoder.normalizedSpelling("Grüße") == "grusse")
let session = LatinSwipeSession()
let points = stroke("hello", order: .qwerty)
session.begin(points[0], arrangement: .qwerty, width: 440)
for p in points.dropFirst() { session.append(p, arrangement: .qwerty, width: 440) }
precondition(session.isLikelyGlide)
session.reset()
precondition(session.points.isEmpty)
print("Latin swipe geometry, normalization and EN/DE ranking: PASS")
  }
}
