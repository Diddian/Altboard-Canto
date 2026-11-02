import Foundation
import UIKit

struct LatinWordSuggestion: Identifiable, Equatable {
  let text: String
  let language: String
  var id: String { language + "|" + text.lowercased() }
}

/// Offline, OS-backed spelling completions for each preferred language that
/// UITextChecker has available (especially English and German). No network,
/// no text upload, no separate model download or writing-language toggle.
/// A short built-in vocabulary covers common words when iOS dictionaries are
/// unavailable to a keyboard extension.
@MainActor
final class LatinWordSuggestions {
  static let shared = LatinWordSuggestions()

  private let checker = UITextChecker()
  private let defaults = AppGroup.sharedDefaults
  private let storageKey = "canto.latin.selectedSuggestions"

  private init() {}

  func choices(for typed: String, preferred: [String], limit: Int = 9) -> [LatinWordSuggestion] {
    guard (2...32).contains(typed.count) else { return [] }
    let codes = LatinWordSuggestionPolicy.preferredCodes(preferred)
    guard !codes.isEmpty else { return [] }

    let available = UITextChecker.availableLanguages
    let installed = LatinWordSuggestionPolicy.checkerLocales(
      preferred: preferred, available: available
    )
    let range = NSRange(location: 0, length: typed.utf16.count)
    var collected = [LatinWordSuggestion]()
    var seen = Set<String>()

    func collect(_ words: [String], code: String) {
      for raw in words.prefix(12) {
        guard (2...36).contains(raw.count),
              raw.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { continue }
        let text = LatinWordSuggestionPolicy.matchCapitalization(raw, typed: typed)
        let normalized = text.lowercased()
        guard normalized != typed.lowercased(),
              seen.insert(normalized).inserted else { continue }
        collected.append(LatinWordSuggestion(text: text, language: code))
      }
    }

    for code in codes {
      if let locale = installed.first(where: { $0.preference == code })?.identifier {
        let completions = checker.completions(
          forPartialWordRange: range, in: typed, language: locale
        ) ?? []
        collect(completions, code: code)
        if typed.count >= 3 {
          let guesses = checker.guesses(forWordRange: range, in: typed, language: locale) ?? []
          collect(guesses, code: code)
        }
      }

      // iOS's dictionary set varies by device. Keep small deterministic
      // English/German completions, even when the OS has no word lists.
      if code == "en" || code == "de" {
        collect(Self.commonWords[code]?.filter {
          $0.lowercased().hasPrefix(typed.lowercased())
        } ?? [], code: code)
      }
    }

    // Selected suggestions are learned locally, just as Cantonese choices
    // already are. There is no collection of uncommitted typed text.
    let counts = defaults?.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    return Array(collected.enumerated().sorted { lhs, rhs in
      let a = counts[lhs.element.id] ?? 0
      let b = counts[rhs.element.id] ?? 0
      return a == b ? lhs.offset < rhs.offset : a > b
    }.prefix(max(1, limit)).map(\.element))
  }

  func remember(_ suggestion: LatinWordSuggestion) {
    var counts = defaults?.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    counts[suggestion.id] = min(10_000, (counts[suggestion.id] ?? 0) + 1)
    if counts.count > 900 {
      counts = Dictionary(uniqueKeysWithValues:
        counts.sorted { $0.value > $1.value }.prefix(500).map { ($0.key, $0.value) })
    }
    defaults?.set(counts, forKey: storageKey)
  }

  static let commonWords: [String: [String]] = [
    "en": [
      "about", "above", "after", "again", "also", "always", "another", "answer",
      "anything", "apple", "around", "because", "before", "Berlin", "better",
      "book", "business", "can", "change", "check", "city", "come", "company",
      "could", "day", "different", "doing", "done", "each", "email", "English",
      "enough", "even", "every", "example", "feel", "find", "first", "food",
      "friend", "from", "German", "Germany", "give", "good", "great", "have",
      "hello", "help", "here", "history", "home", "hope", "how", "idea",
      "important", "information", "into", "just", "keyboard", "know", "language",
      "last", "later", "learn", "left", "like", "little", "long", "look",
      "make", "many", "maybe", "message", "might", "more", "morning", "much",
      "music", "need", "never", "next", "night", "nothing", "now", "number",
      "often", "okay", "only", "other", "people", "place", "please", "possible",
      "question", "really", "right", "same", "school", "sentence", "should",
      "some", "someone", "something", "start", "still", "story", "such",
      "talk", "thank", "thanks", "their", "there", "these", "thing", "think",
      "this", "those", "through", "time", "today", "tomorrow", "under",
      "understand", "until", "very", "want", "water", "week", "well",
      "what", "when", "where", "which", "while", "whole", "why",
      "will", "with", "without", "word", "work", "world", "would",
      "write", "writing", "year", "yesterday", "your"
    ],
    "de": [
      "aber", "Abend", "alle", "alles", "also", "andere", "Anfang", "Angst",
      "antworten", "Arbeit", "arbeiten", "auch", "auf", "aus", "Bahn",
      "Beispiel", "Berlin", "besser", "bestimmt", "bezahlen", "bitte",
      "bleiben", "brauchen", "danke", "danken", "dann", "darf", "dass",
      "deine", "denken", "Deutsch", "Deutschland", "dich", "diese",
      "direkt", "doch", "dort", "durch", "eigentlich", "einfach", "einige",
      "einmal", "entschuldigung", "erklären", "erste", "etwas", "Familie",
      "finden", "Frage", "fragen", "frei", "Freitag", "Freund", "früh",
      "fühlen", "geben", "gehen", "genau", "gerade", "gern", "gesagt",
      "Geschichte", "gestern", "gibt", "glaube", "gleich", "glücklich",
      "groß", "gut", "gute", "Guten", "habe", "haben", "Hallo",
      "heute", "hier", "Hilfe", "holen", "hören", "immer", "interessant",
      "ja", "jeden", "jetzt", "kann", "kaufen", "kein", "kennen",
      "Kinder", "klein", "kommen", "können", "kurz", "lang", "lange",
      "lassen", "leben", "leider", "lernen", "lesen", "Liebe", "lieb",
      "machen", "manchmal", "mehr", "Meinung", "Menschen", "mich",
      "Mittag", "morgen", "möglich", "müssen", "nach", "Nachricht",
      "nächste", "nicht", "noch", "oder", "ohne", "richtig", "sagen",
      "schauen", "schlecht", "schnell", "schön", "Schule", "schreiben",
      "sehen", "sein", "sehr", "selbst", "sicher", "soll", "später",
      "sprechen", "Stadt", "stehen", "Tag", "tatsächlich", "Telefon",
      "Termin", "trotzdem", "über", "Uhr", "und", "unser", "unter",
      "verstehen", "vielleicht", "viele", "von", "vor", "warum",
      "warten", "weiß", "welche", "wenn", "wer", "werden", "wichtig",
      "wieder", "wie", "wirklich", "wissen", "Woche", "wohnen",
      "wollen", "wurde", "Zeit", "zeigen", "zusammen", "zwischen"
    ]
  ]
}
