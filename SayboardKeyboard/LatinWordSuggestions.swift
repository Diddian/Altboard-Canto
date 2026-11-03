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

  func fastChoices(for typed: String, preferred: [String], limit: Int = 6)
    -> [LatinWordSuggestion] {
    let codes = LatinWordSuggestionPolicy.preferredCodes(preferred)
    guard (2...32).contains(typed.count) else { return [] }
    var result = [LatinWordSuggestion]()
    var seen = Set<String>()
    for code in codes where code == "en" || code == "de" {
      let words = Self.commonWords[code] ?? []
      let phrases = LatinWordSuggestionPolicy.splitPhraseCorrections(
        for: typed, dictionary: words, limit: 2
      )
      let lexicon = code == "en"
        ? SwipeWordLexicon.shared.prefixMatches(typed, limit: 10) : []
      let prefixes = words.filter {
        $0.lowercased().hasPrefix(typed.lowercased())
          && $0.lowercased() != typed.lowercased()
      }
      for raw in phrases + lexicon + prefixes {
        let text = LatinWordSuggestionPolicy.matchCapitalization(raw, typed: typed)
        if seen.insert(text.lowercased()).inserted {
          result.append(LatinWordSuggestion(text: text, language: code))
        }
        if result.count >= limit { return result }
      }
    }
    return result
  }

  func choices(for typed: String, preferred: [String], limit: Int = 9) -> [LatinWordSuggestion] {
    guard (2...32).contains(typed.count) else { return [] }
    let codes = LatinWordSuggestionPolicy.preferredCodes(preferred)
    guard !codes.isEmpty else { return [] }

    let available = UITextChecker.availableLanguages
    let installed = LatinWordSuggestionPolicy.checkerLocales(
      preferred: preferred, available: available
    )
    let range = NSRange(location: 0, length: typed.utf16.count)
    var collected = fastChoices(for: typed, preferred: preferred, limit: limit)
    var seen = Set(collected.map { $0.text.lowercased() })

    func collect(_ words: [String], code: String) {
      for raw in words.prefix(12) {
        guard (2...36).contains(raw.count),
              !raw.contains("\n") else { continue }
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

  /// Words saved by an explicit alternate tap are eligible for future swipes.
  /// Raw paths and host text are never persisted.
  func learnedSwipeWords(preferred: [String]) -> [String] {
    let permitted = Set(LatinWordSuggestionPolicy.preferredCodes(preferred))
    let counts = self.defaults?.dictionary(forKey: self.storageKey) as? [String: Int] ?? [:]
    return counts.filter { entry in
      let pieces = entry.key.split(separator: "|", maxSplits: 1).map(String.init)
      return pieces.count == 2 && permitted.contains(pieces[0])
        && entry.value > 0 && (2...32).contains(pieces[1].count)
    }.sorted { $0.value > $1.value }.prefix(120).compactMap { entry in
      entry.key.split(separator: "|", maxSplits: 1).last.map(String.init)
    }
  }

  static let commonWords: [String: [String]] = [
    "en": [
      "about", "above", "after", "again", "also", "always", "another", "answer",
      "anything", "apple", "around", "because", "before", "Berlin", "better",
      "book", "business", "can", "change", "check", "city", "come", "company", "become", "becoming",
      "could", "day", "different", "doing", "done", "each", "email", "English",
      "enough", "even", "ever", "evermore", "every", "example", "feel", "find", "first", "food",
      "friend", "from", "German", "Germany", "give", "good", "great", "have",
      "hello", "help", "here", "history", "home", "hope", "how", "idea",
      "important", "information", "into", "just", "keyboard", "know", "language",
      "last", "later", "learn", "left", "like", "little", "long", "look",
      "make", "many", "maybe", "message", "might", "more", "morning", "much",
      "music", "need", "never", "next", "night", "nothing", "now", "number",
      "often", "okay", "only", "other", "people", "place", "please", "possible",
      "question", "really", "right", "same", "school", "sentence", "should",
      "penetrate", "penetration", "strange", "stranger", "strangely", "tight",
      "tightly", "triangle", "translate", "translation", "transcribe",
      "transcription", "technology", "technical", "testing", "testimony",
      "temperature", "temporary", "important", "interesting", "interested",
      "international", "information", "influence", "influential",
      "difference", "different", "difficult", "difficulty", "development",
      "developing", "developer", "deliver", "delivering", "delivery",
      "direction", "discussion", "discover", "discovery", "description",
      "communication", "community", "communicate", "connection",
      "conversation", "conversational", "consider", "consideration",
      "conclusion", "consequence", "confidence", "confident", "continue",
      "continuation", "continuous", "correct", "correction", "correctly",
      "character", "characteristic", "challenge", "challenging", "changeable",
      "understanding", "understandable", "understood", "unnecessary",
      "necessary", "necessarily", "naturally", "natural", "nature",
      "experience", "experienced", "experiment", "experimental",
      "environment", "everything", "everywhere", "especially", "essential",
      "expression", "expressing", "explain", "explanation", "example",
      "forward", "following", "function", "functionality", "future",
      "generation", "generally", "government", "happening", "happiness",
      "hardship", "hardware", "hospital", "immediately", "improve",
      "improvement", "improving", "implementation", "implement",
      "individual", "independent", "investigate", "investigation",
      "language", "languages", "learning", "learned", "listening",
      "literally", "location", "managing", "management", "meaning",
      "meaningful", "measurement", "microphone", "movement",
      "paragraph", "parliament", "particular", "particularly",
      "performance", "performing", "permission", "personal", "personally",
      "physical", "position", "possible", "possibly", "powerful",
      "practical", "practice", "problem", "problems", "processing",
      "production", "professional", "progress", "project", "projects",
      "quality", "quantity", "questioning", "recognition", "recognize",
      "relationship", "relationships", "reliable", "reliability",
      "remember", "reminder", "repeated", "repeating", "replacement",
      "represent", "representation", "responsibility", "respond",
      "response", "satisfaction", "satisfied", "situation", "software",
      "something", "sometimes", "speaking", "specifically", "specific",
      "standard", "standing", "struggling", "structure", "successful",
      "sufficient", "sustainability", "system", "systematic", "systematically",
      "some", "someone", "something", "start", "still", "story", "such",
      "talk", "thank", "thanks", "that's", "that", "their", "there", "there's", "these", "thing", "think",
      "to", "of", "in", "on", "it", "it's", "is", "at", "as", "be", "by", "we", "we're", "he",
      "me", "my", "do", "don't", "can't", "I'm", "go", "so", "up", "us", "an", "am", "or", "if", "no", "hi",
      "this", "those", "through", "time", "today", "tomorrow", "under",
      "you", "yourself", "younger", "young", "not", "note",
      "actually", "actual", "perhaps", "people", "some", "someone",
      "understand", "until", "very", "want", "water", "week", "well",
      "what", "what's", "when", "where", "which", "while", "whole", "why",
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
      "wollen", "wurde", "Zeit", "zeigen", "zusammen", "zwischen",
      "zu", "im", "in", "an", "am", "es", "er", "du", "ob", "um", "da", "ab",
    ]
  ]
}
