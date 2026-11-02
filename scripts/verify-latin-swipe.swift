import Foundation

func stroke(_ word: String, order: LetterKeyArrangement) -> [LatinSwipePoint] {
  let centers = LatinSwipeDecoder.centers(arrangement: order, fullWidth: 440)
  return word.lowercased().compactMap { centers[String($0)] }
}

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
precondition(LatinSwipeDecoder.rank(
  path: stroke("hi", order: .qwerty), arrangement: .qwerty,
  fullWidth: 440, words: ["hi"]).isEmpty)
precondition(LatinSwipeDecoder.normalizedSpelling("Grüße") == "grusse")
var session = LatinSwipeSession()
let points = stroke("hello", order: .qwerty)
session.begin(points[0], arrangement: .qwerty, width: 440)
for p in points.dropFirst() { session.append(p, arrangement: .qwerty, width: 440) }
precondition(session.isLikelyGlide)
session.reset()
precondition(session.points.isEmpty)
print("Latin swipe geometry, normalization and EN/DE ranking: PASS")
