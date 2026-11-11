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

  func fastChoices(for typed: String, preferred: [String], limit: Int = 6,
                   spellCheckEnabled: Bool = false)
    -> [LatinWordSuggestion] {
    let codes = LatinWordSuggestionPolicy.preferredCodes(preferred)
    let languageBoosts = LanguagePriority.boosts(preferred)
    guard (2...32).contains(typed.count) else { return [] }
    var result = [LatinWordSuggestion]()
    var seen = Set<String>()
    // Previously confirmed custom words must be searchable again, including
    // a neutral language bucket when both English and German were enabled.
    let selected = defaults?.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    let supported = Set(codes.filter { $0 == "en" || $0 == "de" })
    let learned = selected.compactMap { key, count -> (LatinWordSuggestion, Int)? in
      let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
      guard count > 0, parts.count == 2,
            supported.contains(parts[0]) || (parts[0] == "und" && !supported.isEmpty),
            parts[1].hasPrefix(typed.lowercased()),
            parts[1] != typed.lowercased(),
            (2...32).contains(parts[1].count) else { return nil }
      return (LatinWordSuggestion(text: parts[1], language: parts[0]), count)
    }.sorted {
      if $0.1 != $1.1 { return $0.1 > $1.1 }
      let left = languageBoosts[$0.0.language] ?? 0
      let right = languageBoosts[$1.0.language] ?? 0
      return left == right ? $0.0.text < $1.0.text : left > right
    }
    for item in learned.prefix(min(3, limit)) {
      let suggestion = item.0
      if seen.insert(suggestion.text.lowercased()).inserted {
        result.append(LatinWordSuggestion(
          text: LatinWordSuggestionPolicy.matchCapitalization(suggestion.text, typed: typed),
          language: suggestion.language
        ))
      }
    }
    // A few bounded reviewed slang/shortform completions; never auto-expand.
    for choice in InformalNgramStore.shared.completions(
      for: typed, preferred: preferred, limit: min(3, limit)
    ) where choice.text.lowercased() != typed.lowercased() {
      if seen.insert(choice.text.lowercased()).inserted { result.append(choice) }
    }
    for code in codes where code == "en" || code == "de" {
      let words = Self.commonWords[code] ?? []
      let phrases = spellCheckEnabled
        ? LatinWordSuggestionPolicy.splitPhraseCorrections(for: typed, dictionary: words, limit: 2)
        : []
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

  func choices(for typed: String, preferred: [String], context: String? = nil,
               limit: Int = 9, spellCheckEnabled: Bool = false) -> [LatinWordSuggestion] {
    guard (2...32).contains(typed.count) else { return [] }
    let codes = LatinWordSuggestionPolicy.preferredCodes(preferred)
    let languageBoosts = LanguagePriority.boosts(preferred)

    let available = UITextChecker.availableLanguages
    let installed = LatinWordSuggestionPolicy.checkerLocales(
      preferred: preferred, available: available
    )
    let range = NSRange(location: 0, length: typed.utf16.count)
    var collected = fastChoices(for: typed, preferred: preferred, limit: limit,
                                spellCheckEnabled: spellCheckEnabled)
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
        if spellCheckEnabled && typed.count >= 3 {
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

    // Context only reorders explicit choices; personal selection counts win.
    // Never retain host text or silently replace an abbreviation.
    let weights = InformalNgramStore.shared.contextWeights(
      context: context, current: typed, preferred: preferred
    )
    let counts = defaults?.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    func score(_ candidate: LatinWordSuggestion) -> Int {
      let token = candidate.text.lowercased()
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
      let saved = (counts[candidate.id] ?? 0)
        + (candidate.language == "und" ? 0 : (counts["und|" + token] ?? 0))
      return saved * 32 + (weights[candidate.language + "|" + token] ?? 0)
        + (languageBoosts[candidate.language] ?? 0)
    }
    return Array(collected.enumerated().sorted { lhs, rhs in
      let a = score(lhs.element), b = score(rhs.element)
      return a == b ? lhs.offset < rhs.offset : a > b
    }.prefix(max(1, limit)).map(\.element))
  }

  /// An opt-in correction must be a unique one-edit candidate and must not
  /// be a valid word in any chosen language. No host text is stored.
  func automaticCorrection(for typed: String, preferred: [String]) -> String? {
    guard (4...24).contains(typed.count),
          !self.recognizesWholeWord(typed, preferred: preferred) else { return nil }
    let locales = LatinWordSuggestionPolicy.checkerLocales(
      preferred: preferred, available: UITextChecker.availableLanguages
    )
    guard !locales.isEmpty else { return nil }
    let range = NSRange(location: 0, length: typed.utf16.count)
    var choices = Set<String>()
    for locale in locales {
      let error = self.checker.rangeOfMisspelledWord(
        in: typed, range: range, startingAt: 0, wrap: false, language: locale.identifier
      )
      if error.location == NSNotFound { return nil }
      let candidates = (self.checker.guesses(
        forWordRange: range, in: typed, language: locale.identifier
      ) ?? []).filter {
        LatinWordSuggestionPolicy.oneEditApart(typed.lowercased(), $0.lowercased())
          && !$0.contains(" ") && (2...32).contains($0.count)
      }
      guard candidates.count == 1, let candidate = candidates.first else { continue }
      choices.insert(candidate.lowercased())
    }
    guard choices.count == 1, let word = choices.first else { return nil }
    return LatinWordSuggestionPolicy.matchCapitalization(word, typed: typed)
  }

  /// A buffered shape spelling is kept as Latin only after an actual word
  /// check, not merely because it resembles the start of a Chinese code.
  func recognizesWholeWord(_ typed: String, preferred: [String]) -> Bool {
    guard (1...32).contains(typed.count) else { return false }
    let lower = typed.lowercased()
    if InformalNgramStore.shared.hasTerm(typed, preferred: preferred) { return true }
    let codes = LatinWordSuggestionPolicy.preferredCodes(preferred)
      .filter { $0 == "en" || $0 == "de" }
    guard !codes.isEmpty else { return false }
    let selected = defaults?.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    if (selected["und|" + lower] ?? 0) > 0 ||
       codes.contains(where: { (selected[$0 + "|" + lower] ?? 0) > 0 }) {
      return true
    }
    if codes.contains("en") && (lower == "i" || lower == "a") { return true }
    if codes.contains("en") && SwipeWordLexicon.shared.contains(lower) { return true }
    for code in codes {
      if Self.commonWords[code]?.contains(where: { $0.lowercased() == lower }) == true {
        return true
      }
    }
    let range = NSRange(location: 0, length: typed.utf16.count)
    for locale in LatinWordSuggestionPolicy.checkerLocales(
      preferred: preferred, available: UITextChecker.availableLanguages
    ) where codes.contains(locale.preference) {
      let error = self.checker.rangeOfMisspelledWord(
        in: typed, range: range, startingAt: 0, wrap: false,
        language: locale.identifier
      )
      if error.location == NSNotFound { return true }
    }
    return false
  }

  func nextWords(after context: String?, preferred: [String], limit: Int = 6)
    -> [LatinWordSuggestion] {
    let words = InformalNgramStore.shared.nextWords(
      after: context, preferred: preferred, limit: limit
    )
    let counts = defaults?.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    // Do not write user context back to the language model. Confirmed Latin
    // choices can only advance an existing contextual candidate three places.
    return words.enumerated().sorted { a, b in
      let aCount = (counts[a.element.id] ?? 0)
        + (counts["und|" + a.element.text.lowercased()] ?? 0)
      let bCount = (counts[b.element.id] ?? 0)
        + (counts["und|" + b.element.text.lowercased()] ?? 0)
      let aBoost = min(3, max(0, aCount / 2))
      let bBoost = min(3, max(0, bCount / 2))
      let left = a.offset - aBoost, right = b.offset - bBoost
      return left == right ? a.offset < b.offset : left < right
    }.map(\.element)
  }

  func remember(_ suggestion: LatinWordSuggestion) {
    guard ["en", "de", "yue", "und"].contains(suggestion.language) else { return }
    let counts = defaults?.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    defaults?.set(
      ConfirmedChoiceLearning.increment(
        suggestion.id, in: counts, trimAt: 900, retain: 500
      ),
      forKey: storageKey
    )
  }

  /// A word selected from a swipe-alternative strip is a confirmed choice.
  /// Do not learn automatically committed first guesses or ambiguous words
  /// that could belong to both enabled languages.
  func rememberSwipeAlternative(_ word: String, preferred: [String]) {
    let codes = LatinWordSuggestionPolicy.preferredCodes(preferred)
      .filter { $0 == "en" || $0 == "de" }
    guard (2...32).contains(word.count), !codes.isEmpty else { return }
    let matching = codes.filter { code in
      if code == "en" && SwipeWordLexicon.shared.contains(word.lowercased()) {
        return true
      }
      return Self.commonWords[code]?.contains(where: {
        $0.caseInsensitiveCompare(word) == .orderedSame
      }) == true
    }
    let selectedLanguage: String?
    if matching.count == 1 { selectedLanguage = matching[0] }
    else if codes.count == 1 { selectedLanguage = codes[0] }
    else { selectedLanguage = "und" }
    guard let selectedLanguage else { return }
    remember(LatinWordSuggestion(text: word, language: selectedLanguage))
  }

  /// An unfamiliar word is added only after the user selects its
  /// quoted literal. Never learn raw gestures or unconfirmed host text.
  @discardableResult
  func rememberCustom(_ word: String, preferred: [String]) -> Bool {
    let cleaned = word.lowercased()
    guard (3...32).contains(cleaned.count),
          let first = cleaned.first, let last = cleaned.last,
          first.isLetter, last.isLetter,
          cleaned.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }),
          defaults != nil
    else { return false }
    let codes = LatinWordSuggestionPolicy.preferredCodes(preferred)
      .filter { $0 == "en" || $0 == "de" }
    guard !codes.isEmpty else { return false }
    let matching = codes.filter { code in
      Self.commonWords[code]?.contains(where: {
        $0.caseInsensitiveCompare(cleaned) == .orderedSame
      }) == true
    }
    let language = matching.count == 1 ? matching[0] :
      (codes.count == 1 ? codes[0] : "und")
    self.remember(LatinWordSuggestion(text: cleaned, language: language))
    return true
  }

  /// Words saved by an explicit alternate tap are eligible for future swipes.
  /// Raw paths and host text are never persisted.
  func learnedSwipeWords(preferred: [String]) -> [String] {
    var permitted = Set(LatinWordSuggestionPolicy.preferredCodes(preferred))
    if !permitted.isDisjoint(with: ["en", "de"]) { permitted.insert("und") }
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
      // Conversational and informal spellings are valid swipe targets.
      "aite", "wanna", "gonna", "gotta", "kinda", "sorta", "lemme", "gimme",
      "dunno", "ain't", "y'all", "nope", "yup", "nah", "bruh", "sus",
      "lowkey", "highkey", "tho", "cuz", "tbh", "idk", "thinner",
      "chillin", "vibing", "awesome", "legit", "yikes", "yolo", "btw",
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
      // Informal spoken German, including common QWERTZ swipe words.
      "naja", "joa", "jup", "nö", "krass", "Digga", "Diggi",
      "Alter", "boah", "Moin", "Jein", "Tschüss", "chillen",
      "chillig", "Bock", "ähm", "öhm", "läuft", "safe", "stabil",
      "mega", "geil", "voll", "echt", "quasi", "halt", "achso",
      "achja", "Brudi", "hammer", "nice", "lol", "nee",
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

