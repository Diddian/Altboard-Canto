import Foundation
@main
enum VerifySchemePreference {
  static func main() {
    precondition(CantoneseSchemePreference.inferredScheme(input: "kui", canonical: "keoi5") == "sidney")
    precondition(CantoneseSchemePreference.inferredScheme(input: "keui", canonical: "keoi5") == "yale")
    precondition(CantoneseSchemePreference.inferredScheme(input: "keoi", canonical: "keoi5") == "plain")
    precondition(CantoneseSchemePreference.inferredScheme(input: "m", canonical: "m4") == nil)
    precondition(CantoneseSchemePreference.preferred(["sidney": 6]) == nil)
    precondition(CantoneseSchemePreference.preferred(["sidney": 10, "plain": 1, "yale": 1]) == "sidney")
  }
}
