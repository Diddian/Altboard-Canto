import Foundation
@main
enum VerifySchemePreference {
  static func main() {
    precondition(CantoneseSchemePreference.inferredScheme(input: "kui", canonical: "keoi5") == "sidney")
    precondition(CantoneseSchemePreference.inferredScheme(input: "keui", canonical: "keoi5") == "yale")
    precondition(CantoneseSchemePreference.inferredScheme(input: "keoi", canonical: "keoi5") == "plain")
    precondition(CantoneseSchemePreference.inferredScheme(input: "m", canonical: "m4") == nil)
    precondition(CantoneseSchemePreference.inferredScheme(input: "jau", canonical: "zau6") == "traditional")
    precondition(CantoneseSchemePreference.inferredScheme(input: "chaan", canonical: "caan4") == "traditional")
    precondition(CantoneseSchemePreference.preferred(["traditional": 5]) == "yale")
    precondition(CantoneseSchemePreference.preferred(["traditional": 5, "sidney": 2]) == "sidney")
    precondition(CantoneseSchemePreference.preferred(["traditional": 5, "plain": 10]) == nil)
    precondition(CantoneseSchemePreference.preferred(["sidney": 6]) == nil)
    precondition(CantoneseSchemePreference.preferred(["sidney": 10, "plain": 1, "yale": 1]) == "sidney")
  }
}
