import Testing

@Suite("Technical transcription formatting")
struct TechnicalTextFormatterTests {
  @Test func numericDecimalGigabytes() {
    #expect(TechnicalTextFormatter.format("Give it 1.7 gigabytes of memory.") ==
      "Give it 1.7 GB of memory.")
  }

  @Test func spelledDecimalGigabytes() {
    #expect(TechnicalTextFormatter.format("I need one point seven gigabytes") ==
      "I need 1.7 GB")
  }

  @Test func digitsAndUnits() {
    #expect(TechnicalTextFormatter.format("seven gigabytes and 500 megabytes") ==
      "7 GB and 500 MB")
  }

  @Test func processorFrequency() {
    #expect(TechnicalTextFormatter.format("two point five gigahertz") == "2.5 GHz")
  }

  @Test func cantoneseDigits() {
    #expect(TechnicalTextFormatter.format("我個硬碟有一點七 gigabytes咋") ==
      "我個硬碟有1.7 GB咋")
  }

  @Test func germanDecimal() {
    #expect(TechnicalTextFormatter.format("eins komma sieben Gigabyte") == "1.7 GB")
  }

  @Test func bitsAreNotBytes() {
    #expect(TechnicalTextFormatter.format("two gigabits") == "2 Gb")
    #expect(TechnicalTextFormatter.format("two gigabytes") == "2 GB")
  }

  @Test func preserveOrdinaryProse() {
    #expect(TechnicalTextFormatter.format("I said one point seven languages, not gigabytes.") ==
      "I said one point seven languages, not gigabytes.")
  }

  @Test func preserveMisrecognizedNumerals() {
    #expect(TechnicalTextFormatter.format("seven gigabytes") == "7 GB")
  }

  @Test func preserveTechnicalAbbreviations() {
    #expect(TechnicalTextFormatter.format("1.7 GB and 3 GHz") == "1.7 GB and 3 GHz")
  }
}
