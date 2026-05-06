import Tekkon
import Testing
@testable import Typewriter

@Suite("MixedInputRawBufferTests", .serialized)
struct MixedInputRawBufferTests {
  @Test func receiveDoesNotMutateRawBufferWhenTerminalSuffixValidates() {
    var buffer = MixedInputRawBuffer(parser: .ofDachen)

    #expect(buffer.receive("s") == nil)
    #expect(buffer.rawBuffer == "s")
    #expect(buffer.displayText == "s")

    #expect(buffer.receive("u") == nil)
    #expect(buffer.rawBuffer == "su")
    #expect(buffer.displayText == "su")

    let commit = buffer.receive("3")
    #expect(commit == .init(literalPrefix: "", suffix: "su3", phonabet: "ㄋㄧˇ"))
    #expect(buffer.rawBuffer == "su3")
  }

  @Test func asciiPrefixRemainsInValidatorBufferAfterTerminalSuffixMatches() {
    var buffer = MixedInputRawBuffer(parser: .ofDachen)

    for key in Array("test su") {
      _ = buffer.receive(String(key))
    }

    #expect(buffer.rawBuffer == "test su")
    let commit = buffer.receive("3")
    #expect(commit == .init(literalPrefix: "test ", suffix: "su3", phonabet: "ㄋㄧˇ"))
    #expect(buffer.rawBuffer == "test su3")
  }

  @Test func shortSuffixDoesNotPeelEnglishLookingToken() {
    var buffer = MixedInputRawBuffer(parser: .ofDachen)

    for key in Array("discordu") {
      _ = buffer.receive(String(key))
    }
    let commit = buffer.receive("6")

    #expect(commit == nil)
    #expect(buffer.rawBuffer == "discordu6")
  }

  @Test func spaceToneValidatesTerminalSuffixAfterPunctuationWithoutMutatingBuffer() {
    var buffer = MixedInputRawBuffer(parser: .ofDachen)

    for key in Array("，5p") {
      _ = buffer.receive(String(key))
    }
    let commit = buffer.receive(" ")

    #expect(commit == .init(literalPrefix: "，", suffix: "5p ", phonabet: "ㄓㄣ"))
    #expect(buffer.rawBuffer == "，5p ")
  }

  @Test func activeTriePrefixAdvancesPerKeyAndBackspaceRestoresParent() {
    var buffer = MixedInputRawBuffer(parser: .ofDachen)

    #expect(buffer.receive("s") == nil)
    #expect(buffer.activeTriePrefix == .init(suffix: "s", phonabet: "ㄋ", state: .prefix))

    #expect(buffer.receive("u") == nil)
    #expect(buffer.activeTriePrefix == .init(suffix: "su", phonabet: "ㄋㄧ", state: .prefix))

    let firstBackspace = buffer.backspace()
    #expect(firstBackspace)
    #expect(buffer.rawBuffer == "s")
    #expect(buffer.activeTriePrefix == .init(suffix: "s", phonabet: "ㄋ", state: .prefix))

    let secondBackspace = buffer.backspace()
    #expect(secondBackspace)
    #expect(buffer.rawBuffer.isEmpty)
    #expect(buffer.activeTriePrefix == nil)
  }

  @Test func deadKeyRestartsFromCurrentKeyAndBackspaceRestoresPreviousFrame() {
    var buffer = MixedInputRawBuffer(parser: .ofDachen)

    #expect(buffer.receive("s") == nil)
    #expect(buffer.receive("u") == nil)
    #expect(buffer.receive("2") == nil)
    // `su2` is not a live Dachen syllable path; incremental traversal must not
    // keep pretending the whole suffix is live. It restarts from the current key.
    #expect(buffer.activeTriePrefix?.suffix == "2")

    #expect(buffer.receive("k") == nil)
    #expect(buffer.rawBuffer == "su2k")
    #expect(buffer.activeTriePrefix?.suffix == "2k")

    let didBackspace = buffer.backspace()
    #expect(didBackspace)
    #expect(buffer.rawBuffer == "su2")
    #expect(buffer.activeTriePrefix?.suffix == "2")
  }

  @Test func findsTonedSuffixForStandaloneZhuyin() {
    let match = MixedInputRawBuffer.longestTonedSuffix(in: "su3", parser: .ofDachen)
    #expect(match == .init(suffix: "su3", phonabet: "ㄋㄧˇ"))
  }

  @Test func findsLongestTonedSuffixAtEndOfRawAsciiPrefix() {
    let match = MixedInputRawBuffer.longestTonedSuffix(in: "testsu3", parser: .ofDachen)
    #expect(match == .init(suffix: "su3", phonabet: "ㄋㄧˇ"))
  }

  @Test func doesNotTreatUntonedSuffixAsZhuyinMatch() {
    let match = MixedInputRawBuffer.longestTonedSuffix(in: "testsu", parser: .ofDachen)
    #expect(match == nil)
  }

  @Test func doesNotTreatPlainEnglishAsTonedZhuyin() {
    let match = MixedInputRawBuffer.longestTonedSuffix(in: "test", parser: .ofDachen)
    #expect(match == nil)
  }

  @Test func matchesXieWithCorrectTone() {
    let match = MixedInputRawBuffer.longestTonedSuffix(in: "vu,4", parser: .ofDachen)
    #expect(match == .init(suffix: "vu,4", phonabet: "ㄒㄧㄝˋ"))
  }

  @Test func dictionaryDerivedSuffixMatcherDoesNotTreatStandaloneO4AsMatch() {
    let match = MixedInputRawBuffer.longestTonedSuffix(in: "o4", parser: .ofDachen)
    #expect(match == nil, "Suffix matcher follows dictionary-derived trie; live composer still handles o4 as ㄟˋ")
  }
}
