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

  @Test func tokenSplitByTerminalSuffixDetectsMidWordSplit() {
    // 典型陷阱：使用者打 `private` 後接大千 `j6`，Trie active suffix 變成
    // `ej6 → ㄍㄨˊ`，會把 `private` 的 `e` 切走。helper 必須回傳
    // 「被切開的完整 token」= "private"，讓 mixed dispatcher 拿去查字典 veto。
    #expect(EnglishWordLexicon.tokenSplitByTerminalSuffix(rawText: "privatej6", suffix: "ej6") == "private")
    // 與 `private` 同形，但 suffix 起點 `t` 之前是 `priva`（合英文 word
    // 規則但不是字典詞），helper 仍應回傳「被切開的 token」字串本身，
    // 由 caller 決定是否查字典。
    #expect(EnglishWordLexicon.tokenSplitByTerminalSuffix(rawText: "privatj6", suffix: "tj6") == "privat")
    // suffix 起點之前不是 ASCII word char → 不算切開英文字。
    #expect(EnglishWordLexicon.tokenSplitByTerminalSuffix(rawText: "j6", suffix: "j6") == nil)
    #expect(EnglishWordLexicon.tokenSplitByTerminalSuffix(rawText: "Y5.6", suffix: "5.6") == nil)
    // suffix 首字元非 ASCII word char。
    #expect(EnglishWordLexicon.tokenSplitByTerminalSuffix(rawText: "hello 3", suffix: " 3") == nil)
    // 被切開的 token 不到 3 char → 視為雜訊不擋。
    #expect(EnglishWordLexicon.tokenSplitByTerminalSuffix(rawText: "abj6", suffix: "bj6") == nil)
    // suffix 與 rawText 末尾不符 → 守門條件。
    #expect(EnglishWordLexicon.tokenSplitByTerminalSuffix(rawText: "hello", suffix: "world") == nil)
  }

  @Test func bundledLexiconVetoesPrivateBeingSplitByZhuyinTerminal() {
    // 端到端：`privatej6` 的 active suffix `ej6` 切開字典詞 `private` →
    // `tokenSplitByTerminalSuffix` 回 "private"、`containsExactToken` 命中 →
    // mixed dispatcher 收到 veto。
    let token = EnglishWordLexicon.tokenSplitByTerminalSuffix(rawText: "privatej6", suffix: "ej6")
    #expect(token == "private")
    #expect(EnglishWordLexicon.bundled.containsExactToken(token ?? ""))
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

  @Test func dictionaryOracleForcesDeadRestartWhenTrieWouldSplitEnglishWord() {
    // 沒裝 oracle 時：`private` + `j6` 走純 Trie，會把 `e` 跟 `j6` 黏成
    // `ej6 → ㄍㄨˊ`，整段 active suffix 變成漢字、把 `private` 切開。
    var noOracle = MixedInputRawBuffer(parser: .ofDachen)
    for k in "privatej6".map(\.description) { _ = noOracle.receive(k) }
    #expect(noOracle.currentTerminalCommit == .init(suffix: "ej6", phonabet: "ㄍㄨˊ"))

    // 裝 oracle 後：oracle 在收 `j` 時偵測到 active suffix `ej` 切開
    // 字典詞 `private` → 強制把當前鍵 dead-restart，active suffix 變
    // `j` 自己；後續 `6` 進來才形成 `j6 → ㄨˊ`，`private` 完整保留。
    var withOracle = MixedInputRawBuffer(parser: .ofDachen)
    withOracle.dictionaryWordSplitOracle = { rawText, suffixStart in
      EnglishWordLexicon.tokenSplitByTerminalSuffix(
        rawText: rawText,
        suffixStart: suffixStart
      ).map(EnglishWordLexicon.bundled.containsExactToken) ?? false
    }
    for k in "private".map(\.description) { _ = withOracle.receive(k) }
    let jTransition = withOracle.receiveWithTransition("j")
    #expect(jTransition == .restartedFromCurrentKey(commit: nil))
    #expect(withOracle.activeTriePrefix?.suffix == "j")
    #expect(withOracle.receiveWithTransition("6") == .continued(commit: .init(
      suffix: "j6",
      phonabet: "ㄨˊ"
    )))
    #expect(withOracle.rawBuffer == "privatej6")
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
