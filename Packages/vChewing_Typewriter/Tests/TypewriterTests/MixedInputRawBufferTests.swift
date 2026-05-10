import Tekkon
import Testing
@testable import Typewriter

@Suite("MixedInputRawBufferTests", .serialized)
struct MixedInputRawBufferTests {
  @Test func bundledEnglishLexiconParsesHunspellStemsForExactLookupOnly() {
    let lexicon = EnglishWordLexicon(hunspellDictionaryText: """
    3
    Hell/SM
    value/nm
    l/AB
    """)

    #expect(lexicon.count == 3)
    #expect(lexicon.containsExactToken("hell"))
    #expect(lexicon.containsExactToken("Hell"))
    #expect(lexicon.containsExactToken("value"))
    #expect(lexicon.containsExactToken("l"))
    #expect(!lexicon.containsExactToken("hello"))
    #expect(!lexicon.containsExactToken("123"))
  }

  @Test func completedASCIITokenRequiresTrailingBoundary() {
    #expect(EnglishWordLexicon.completedASCIIToken(beforeTrailingBoundary: "What the hell ") == "hell")
    #expect(EnglishWordLexicon.completedASCIIToken(beforeTrailingBoundary: "woo ") == "woo")
    #expect(EnglishWordLexicon.completedASCIIToken(beforeTrailingBoundary: "ru ") == nil)
    #expect(EnglishWordLexicon.completedASCIIToken(beforeTrailingBoundary: "Y5.6 ") == nil)
    #expect(EnglishWordLexicon.completedASCIIToken(beforeTrailingBoundary: "hell") == nil)
  }

  @Test func bundledEnglishLexiconContainsWooormDictionaryWords() {
    #expect(EnglishWordLexicon.bundled.count > 40_000)
    #expect(EnglishWordLexicon.bundled.containsExactToken("hell"))
    #expect(EnglishWordLexicon.bundled.containsExactToken("film"))
  }

  @Test func receiveDoesNotMutateRawBufferWhenTerminalSuffixValidates() {
    var buffer = MixedInputRawBuffer(parser: .ofDachen)

    #expect(buffer.receive("s") == nil)
    #expect(buffer.rawBuffer == "s")
    #expect(buffer.displayText == "s")

    #expect(buffer.receive("u") == nil)
    #expect(buffer.rawBuffer == "su")
    #expect(buffer.displayText == "su")

    let commit = buffer.receive("3")
    #expect(commit == .init(suffix: "su3", phonabet: "ㄋㄧˇ"))
    #expect(buffer.rawBuffer == "su3")
  }

  @Test func rawBufferWalksTriePerKeyWithoutPrefixConfirm() {
    var buffer = MixedInputRawBuffer(parser: .ofDachen)

    for key in Array("test su") {
      _ = buffer.receive(String(key))
    }

    #expect(buffer.rawBuffer == "test su")
    let commit = buffer.receive("3")
    #expect(commit == .init(suffix: "su3", phonabet: "ㄋㄧˇ"))
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

    #expect(commit == .init(suffix: "5p ", phonabet: "ㄓㄣ"))
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
    let restartAt2 = buffer.receiveWithTransition("2")
    // `su2` is not a live Dachen syllable path; incremental traversal must not
    // keep pretending the whole suffix is live. It restarts from the current key.
    #expect(restartAt2 == .restartedFromCurrentKey(commit: nil))
    #expect(buffer.activeTriePrefix?.suffix == "2")

    #expect(buffer.receive("k") == nil)
    #expect(buffer.rawBuffer == "su2k")
    #expect(buffer.activeTriePrefix?.suffix == "2k")

    let didBackspace = buffer.backspace()
    #expect(didBackspace)
    #expect(buffer.rawBuffer == "su2")
    #expect(buffer.activeTriePrefix?.suffix == "2")
  }

  @Test func deadRestartReportsTransitionForSingleAsciiBeforeDachenSyllable() {
    var buffer = MixedInputRawBuffer(parser: .ofDachen)

    let yTransition = buffer.receiveWithTransition("Y")
    #expect(yTransition.commit == nil)
    #expect(buffer.rawBuffer == "Y")
    #expect(buffer.receiveWithTransition("5") == .restartedFromCurrentKey(commit: nil))
    #expect(buffer.activeTriePrefix == .init(suffix: "5", phonabet: "ㄓ", state: .prefix))
    #expect(buffer.receive(".") == nil)
    #expect(buffer.receiveWithTransition("6") == .continued(commit: .init(
      suffix: "5.6",
      phonabet: "ㄓㄡˊ"
    )))
  }

  /// 共用 helper：把整段 raw 文字以增量方式餵給 incremental buffer，
  /// 取尾端的 terminal commit。等價於原本已被移除的全掃靜態 API
  /// `longestTonedSuffix(in:parser:)`，但走的是 production 路徑。
  private func incrementalTerminalCommit(
    in rawBuffer: String,
    parser: Tekkon.MandarinParser
  ) -> MixedInputRawBuffer.Commit? {
    var buffer = MixedInputRawBuffer(parser: parser)
    for key in rawBuffer.map(\.description) {
      _ = buffer.receive(key)
    }
    return buffer.currentTerminalCommit
  }

  @Test func findsTonedSuffixForStandaloneZhuyin() {
    let match = incrementalTerminalCommit(in: "su3", parser: .ofDachen)
    #expect(match == .init(suffix: "su3", phonabet: "ㄋㄧˇ"))
  }

  @Test func findsLongestTonedSuffixAtEndOfRawAsciiPrefix() {
    let match = incrementalTerminalCommit(in: "testsu3", parser: .ofDachen)
    #expect(match == .init(suffix: "su3", phonabet: "ㄋㄧˇ"))
  }

  @Test func doesNotTreatUntonedSuffixAsZhuyinMatch() {
    let match = incrementalTerminalCommit(in: "testsu", parser: .ofDachen)
    #expect(match == nil)
  }

  @Test func doesNotTreatPlainEnglishAsTonedZhuyin() {
    let match = incrementalTerminalCommit(in: "test", parser: .ofDachen)
    #expect(match == nil)
  }

  @Test func matchesXieWithCorrectTone() {
    let match = incrementalTerminalCommit(in: "vu,4", parser: .ofDachen)
    #expect(match == .init(suffix: "vu,4", phonabet: "ㄒㄧㄝˋ"))
  }

  @Test func dictionaryDerivedSuffixMatcherDoesNotTreatStandaloneO4AsMatch() {
    let match = incrementalTerminalCommit(in: "o4", parser: .ofDachen)
    #expect(match == nil, "Suffix matcher follows dictionary-derived trie; live composer still handles o4 as ㄟˋ")
  }

  @Test func dachenTrieDataKeepsBareConsonantFirstToneTerminalsForValidReadings() {
    let trie = ZhuyinKeyTrie.shared(for: .ofDachen)
    for key in [
      "1", "q", "a", "z",
      "2", "w", "s", "x",
      "e", "d", "c",
      "r", "f", "v",
      "5", "t", "g", "b",
      "y", "h", "n",
    ] {
      #expect(trie.state(for: [key, " "]) == .terminal)
    }
  }

  @Test func dachenTrieStillKeepsRealSyllablesAlongsideBareConsonantFirstToneTerminals() {
    let trie = ZhuyinKeyTrie.shared(for: .ofDachen)

    #expect(trie.state(for: ["s", "u", "3"]) == .terminal) // ㄋㄧˇ
    #expect(trie.state(for: ["5", ".", "6"]) == .terminal) // ㄓㄡˊ
    #expect(trie.state(for: ["8", " "]) == .terminal) // ㄚ
  }
}
