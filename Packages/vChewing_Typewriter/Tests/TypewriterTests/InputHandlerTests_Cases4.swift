// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation
import Homa
import LMAssemblyMaterials4Tests

import Shared
import Testing

import HomaSharedTestComponents
@testable import LangModelAssembly
@testable import Typewriter

// MARK: - 測試案例 Vol 4 (Mixed Alphanumerical Mode)

extension InputHandlerTests {
  // MARK: Group A — Mixed Buffer Exit Paths

  fileprivate struct MixedBufferExitScenario: Sendable {
    let id: String
    let input: String
    let exitKeyCode: UInt16
    let expectedBufferAfterInput: String
    let expectedCommission: String
    let expectedBufferAfterExit: String
    let escToCleanInputBuffer: Bool
    let expectedStateRawValue: String?
  }

  @Test(arguments: [
    MixedBufferExitScenario(
      id: "IH401A", input: "a=",
      exitKeyCode: KeyCode.kLineFeed.rawValue,
      expectedBufferAfterInput: "", expectedCommission: "a＝",
      expectedBufferAfterExit: "", escToCleanInputBuffer: true,
      expectedStateRawValue: .none
    ),
    MixedBufferExitScenario(
      id: "IH401B", input: "u.",
      exitKeyCode: KeyCode.kBackSpace.rawValue,
      expectedBufferAfterInput: "u.", expectedCommission: "",
      expectedBufferAfterExit: "u", escToCleanInputBuffer: true,
      expectedStateRawValue: .none
    ),
    MixedBufferExitScenario(
      id: "IH401C", input: "abc",
      exitKeyCode: KeyCode.kEscape.rawValue,
      expectedBufferAfterInput: "abc", expectedCommission: "",
      expectedBufferAfterExit: "", escToCleanInputBuffer: false,
      expectedStateRawValue: "Empty"
    ),
    MixedBufferExitScenario(
      id: "IH401D", input: "abc",
      exitKeyCode: KeyCode.kLineFeed.rawValue,
      expectedBufferAfterInput: "abc", expectedCommission: "abc",
      expectedBufferAfterExit: "", escToCleanInputBuffer: true,
      expectedStateRawValue: .none
    ),
  ])
  private func test_IH401_MixedBufferExitPaths(_ s: MixedBufferExitScenario) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    testHandler.prefs.escToCleanInputBuffer = s.escToCleanInputBuffer

    typeSentence(s.input)

    #expect(testHandler.mixedAlphanumericalBuffer == s.expectedBufferAfterInput, "\(s.id) buffer after input")

    let exitEvent = KBEvent.KeyEventData(chars: "", keyCode: s.exitKeyCode).asEvent
    #expect(testHandler.triageInput(event: exitEvent))

    if !s.expectedCommission.isEmpty {
      #expect(testSession.recentCommissions.joined() == s.expectedCommission, "\(s.id) commission")
    }
    #expect(testHandler.mixedAlphanumericalBuffer == s.expectedBufferAfterExit, "\(s.id) buffer after exit")
    if let expectedState = s.expectedStateRawValue {
      #expect(testSession.state.type.rawValue == expectedState, "\(s.id) state after exit")
    }
  }

  /// 測試中英混打模式下，Space 鍵應走注音提交路徑而非 commit ASCII 讀音字串。
  /// 驗證修正前的 bug：「ㄐㄧ 」(Dachen: r+u+Space) 會直接 commit "ㄐㄧ " 純讀音字串。
  /// 修正後：Space 按下時若 composer 有注音內容，應交由 BPMFFullMatchTypewriter 處理，
  /// 進而 commit 對應漢字，而非 ASCII buffer 原文。
  @Test
  func test_IH402_MixedSpacePhoneticCommit() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()

    typeSentence("ru ")

    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    let commissioned = testSession.recentCommissions.joined()
    #expect(!commissioned.contains("ㄐ"), "Space 不應 commit 讀音字串，但得到：\(commissioned)")
  }

  /// Shift + 英文字開頭（大寫）在混輸模式下應保留 ASCII 大寫，
  /// 不得被誤送去注音路徑導致如 "This" -> "Tㄘㄛ"。
  @Test
  func test_IH403_MixedUppercaseLeadStaysASCII() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()

    typeSentence("This")

    #expect(testHandler.mixedAlphanumericalBuffer == "This")
    #expect(testHandler.generateStateOfInputting().displayedText == "This")
    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "This")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
  }

  /// 已有中文節點後，繼續輸入可同時拼成注音的英文字母時，仍先保留 raw buffer；
  /// 不可走 legacy 純注音 continuation path，也不可把 composer reading 疊進 inline。
  @Test
  func test_IH404_ExistingChineseThenPrintableKeysStayRawUntilExplicitFinalize() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄗㄚˊ 咱 -1
    ㄉㄜ˙ 地 -1
    ㄍㄟˇ 給 -1
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    #expect(throws: Never.self) { try testHandler.assembler.insertKey("ㄗㄚˊ") }
    #expect(throws: Never.self) { try testHandler.assembler.insertKey("ㄉㄜ˙") }
    testSession.switchState(testHandler.generateStateOfInputting())

    typeSentence("code")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer == "code")
    #expect(testHandler.generateStateOfInputting().displayedText == "咱地code")

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "咱地code")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
  }

  /// 中英混打時，藍色 inline 應顯示 raw buffer 狀態，
  /// 黑色 tooltip 才顯示目前 Trie/composer 走到的注音。
  @Test
  func test_IH405B_MixedTooltipShowsActiveTriePhonabetOnly() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    defer { testHandler.clear() }

    typeSentence("f")

    #expect(testHandler.mixedAlphanumericalBuffer == "f")
    #expect(testSession.state.displayedText == "f")
    #expect(testSession.state.tooltip == "ㄑ")

    typeSentence("u")

    #expect(testHandler.mixedAlphanumericalBuffer == "fu")
    #expect(testSession.state.displayedText == "fu")
    #expect(testSession.state.tooltip == "ㄑㄧ")
  }

  /// 中英混打時，藍色 inline 應保留使用者實際輸入的 raw case，
  /// 黑色 tooltip 則用 lowercased key tail 走 Trie/composer 顯示注音。
  @Test
  func test_IH405C_MixedTooltipNormalizesUppercaseKeysForPhonabetPreview() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    defer { testHandler.clear() }

    typeSentence("SU")

    #expect(testHandler.mixedAlphanumericalBuffer == "SU")
    #expect(testSession.state.displayedText == "SU")
    #expect(testSession.state.tooltip == "ㄋㄧ")
  }

  /// Mixed alnum tail ending in a two-key syllable must not peel a tiny terminal suffix.
  /// `su2k7` should stay raw instead of peeling `k7` into LM candidate `爹`.
  @Test
  func test_IH405D_MixedAlnumTailDoesNotPeelTinyK7Suffix() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let cleanup = injectTemporaryGrams(testHandler, "ㄜ˙ 爹 -1")
    defer { cleanup(); testHandler.clear() }

    typeSentence("su2k7")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer == "su2k7")
    #expect(testHandler.committableDisplayText(sansReading: true) == "su2k7")
  }

  /// 英文 prefix 後已有中文節點時，active Trie tail 只應出現在 tooltip；
  /// 藍色 inline 不得再把 composer reading 疊進來形成 `ek整ㄍㄜ` 這類混合怪。
  @Test
  func test_IH405E_MixedInlineCompositionDoesNotDuplicateActiveTrieTailReading() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄍㄜˇ 整 -1
    ㄍㄜ 歌 -1
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("ek3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.generateStateOfInputting().displayedText == "整")

    testHandler.clear()
    var stream = MixedInputSegmentStream(parser: testHandler.composer.parser)
    _ = stream.appendRawKey("e")
    _ = stream.appendRawKey("k")
    stream.appendChinese(text: "整", readings: ["ㄍㄜˇ"])
    testHandler.mixedInputSegmentStream = stream
    testHandler.mixedInputRawBuffer.clear()
    testHandler.mixedAlphanumericalBuffer = "ek"
    testSession.switchState(testHandler.generateStateOfInputting())

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer == "ek")
    #expect(testSession.state.displayedText == "ek整")
    #expect(testSession.state.tooltip == "ㄍㄜ")
  }

  /// 純注音連打不能被 mixed inline-prefix continuation path 污染成 raw+中文。
  /// 完成第一個音節後，後續音節應留在一般注音組字路徑，不應把 raw key 留成 inline ASCII prefix。
  @Test
  func test_IH405F_PurePhoneticContinuationDoesNotKeepRawPrefix() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.generateStateOfInputting().displayedText == "你")

    typeSentence("cl3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.generateStateOfInputting().displayedText == "你好")
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好")
  }

  /// 英文前綴 + 注音後綴應透過 Trie/parser 檢查 terminal tail；
  /// 若 suffix 可拼成注音且 LM 有詞，才透過 terminal suffix commit 轉中文。
  /// 參數化覆蓋大小寫 ASCII 前綴（`Hellosu3` / `hellosu3`）。
  @Test(arguments: ["Hellosu3", "hellosu3"])
  func test_IH405_MixedTerminalSuffixASCIIAndPhoneticSuffix(_ mixedPrefixInput: String) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 擬 -1.5
    ㄧˇ 以 -1
    ㄏㄠˇ 好 -1
    ㄏㄠˇ 郝 -1.5
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    #expect(mixedPrefixInput.hasSuffix("su3"))
    let expectedASCIIPrefix = String(mixedPrefixInput.dropLast("su3".count))

    typeSentence(mixedPrefixInput)

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.committableDisplayText(sansReading: true) == expectedASCIIPrefix + "你")
    #expect(testHandler.generateStateOfInputting().displayedText == expectedASCIIPrefix + "你")
    #expect(testHandler.mixedAlphanumericalBuffer == expectedASCIIPrefix)

    typeSentence("cl3")

    let composedText = testHandler.committableDisplayText(sansReading: true)
    #expect(!composedText.isEmpty)
    #expect(composedText == expectedASCIIPrefix + "你好")
    #expect(testHandler.generateStateOfInputting().displayedText == expectedASCIIPrefix + "你好")
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer == expectedASCIIPrefix)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == expectedASCIIPrefix + "你好")
  }

  /// 純注音雙音節在 mixed mode 下用 Space 確認後，
  /// displayText 不得殘留 mixed buffer 內容（例如 `呂方z;`）。
  @Test
  func test_IH406_MixedPurePhoneticSpaceLeavesNoASCIIResidue() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄐㄧ 機 -1
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("ru ")

    #expect(testSession.state.displayedText == "機")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
  }

  /// 已有中文組字後，後續 printable keys（即使同時是合法注音鍵）也必須先進 mixed raw buffer，
  /// 由 Trie validator 延後消歧；不可因為 assembler/composer 非空而走 legacy 純注音 continuation path。
  @Test
  func test_IH406A_MixedCanKeepASCIIAfterChineseComposition() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    defer { testHandler.clear() }

    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup() }

    typeSentence("su3cl3test")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer == "test")
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test")
    #expect(testHandler.generateStateOfInputting().displayedText == "你好test")

    typeSentence("su3cl3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer == "test")
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test你好")
    #expect(testHandler.generateStateOfInputting().displayedText == "你好test你好")
  }

  // MARK: Group C1 — Terminal Suffix with Prior Chinese

  private struct TerminalSuffixWithPriorChineseScenario: Sendable {
    let id: String
    let mixedInput: String
    let expectedCommissions: [String]
    let expectedComposedText: String
    let followUpInput: String?
    let expectedComposedTextAfterFollowUp: String?
  }

  @Test(arguments: [
    TerminalSuffixWithPriorChineseScenario(
      id: "IH407A", mixedInput: "xu.6u4Hellod93",
      expectedCommissions: [], expectedComposedText: "留意Hello凱",
      followUpInput: nil, expectedComposedTextAfterFollowUp: nil
    ),
    TerminalSuffixWithPriorChineseScenario(
      id: "IH407B", mixedInput: "xu.6u4Thisd93",
      expectedCommissions: [], expectedComposedText: "留意This凱",
      followUpInput: nil, expectedComposedTextAfterFollowUp: nil
    ),
  ])
  private func test_IH407_TerminalSuffixWithPriorChinese(_ s: TerminalSuffixWithPriorChineseScenario) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = s.followUpInput != nil
      ? """
      ㄌㄧㄡˊ-ㄧˋ 留意 -2
      ㄌㄧㄡˊ 留 -1
      ㄧˋ 意 -1
      ㄎㄞˇ 凱 -1
      ㄍㄜ 歌 -1
      ㄎㄞˇ-ㄍㄜ 凱歌 -2
      """
      : """
      ㄌㄧㄡˊ-ㄧˋ 留意 -2
      ㄌㄧㄡˊ 留 -1
      ㄧˋ 意 -1
      ㄎㄞˇ 凱 -1
      """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence(s.mixedInput)

    #expect(testSession.recentCommissions == s.expectedCommissions, "\(s.id) commissions")
    #expect(testHandler.committableDisplayText(sansReading: true) == s.expectedComposedText, "\(s.id) composed")
    #expect(!testHandler.mixedAlphanumericalBuffer.isEmpty)

    if let followUp = s.followUpInput, let expectedAfter = s.expectedComposedTextAfterFollowUp {
      typeSentence(followUp)
      #expect(testSession.recentCommissions == s.expectedCommissions, "\(s.id) commissions after follow-up")
      #expect(
        testHandler.committableDisplayText(sansReading: true) == expectedAfter,
        "\(s.id) composed after follow-up"
      )
      #expect(!testHandler.mixedAlphanumericalBuffer.isEmpty)
    }
  }

  // MARK: Group C2 — Terminal Suffix Boundary Cases

  private struct GramSpec: Sendable {
    let rawSequence: String
    let value: String
    let score: Double
  }

  private struct TerminalSuffixBoundaryScenario: Sendable {
    let id: String
    let input: String
    let expectedCommissions: [String]
    let expectedComposedText: String
    let expectedDisplayMustNotContain: String?
    let gramSpecs: [GramSpec]
  }

  @Test(arguments: [
    TerminalSuffixBoundaryScenario(
      id: "IH408A", input: "Twinsu.4",
      expectedCommissions: [], expectedComposedText: "Twin拗",
      expectedDisplayMustNotContain: "又",
      gramSpecs: [
        GramSpec(rawSequence: "u.4", value: "又", score: 999),
        GramSpec(rawSequence: "su.4", value: "拗", score: 100),
      ]
    ),
    TerminalSuffixBoundaryScenario(
      id: "IH408B", input: "This5jp3",
      expectedCommissions: [], expectedComposedText: "This準",
      expectedDisplayMustNotContain: .none,
      gramSpecs: [
        GramSpec(rawSequence: "5jp3", value: "準", score: 100),
        GramSpec(rawSequence: "jp3", value: "穩", score: 999),
      ]
    ),
    TerminalSuffixBoundaryScenario(
      id: "IH408C", input: "thisgjo6",
      expectedCommissions: [], expectedComposedText: "this誰",
      expectedDisplayMustNotContain: .none,
      gramSpecs: [
        GramSpec(rawSequence: "gjo6", value: "誰", score: -2),
        GramSpec(rawSequence: "jo6", value: "為", score: -2),
      ]
    ),
    TerminalSuffixBoundaryScenario(
      id: "IH408D", input: "?c96",
      expectedCommissions: [], expectedComposedText: "？還",
      expectedDisplayMustNotContain: "癌",
      gramSpecs: [
        GramSpec(rawSequence: "c96", value: "還", score: 100),
        GramSpec(rawSequence: "96", value: "癌", score: -1),
      ]
    ),
    TerminalSuffixBoundaryScenario(
      id: "IH408E", input: "testsu3cl3",
      expectedCommissions: [], expectedComposedText: "test你好",
      expectedDisplayMustNotContain: .none,
      gramSpecs: [
        GramSpec(rawSequence: "su3", value: "你", score: -1),
        GramSpec(rawSequence: "cl3", value: "好", score: -1),
        GramSpec(rawSequence: "su3cl3", value: "你好", score: -2),
      ]
    ),
  ])
  private func test_IH408_MixedTerminalSuffixBoundaryCases(_ s: TerminalSuffixBoundaryScenario) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    for spec in s.gramSpecs {
      guard let gram = makeTemporaryGram(
        rawSequence: spec.rawSequence,
        value: spec.value,
        score: spec.score,
        using: testHandler
      ) else {
        Issue.record("Failed to create gram for \(spec.rawSequence)")
        return
      }
      testHandler.currentLM.insertTemporaryData(unigram: gram, isFiltering: false)
    }
    defer { testHandler.currentLM.clearTemporaryData(isFiltering: false); testHandler.clear() }

    typeSentence(s.input)

    #expect(testSession.recentCommissions == s.expectedCommissions, "\(s.id) commissions")
    let currentDisplay = testHandler.committableDisplayText(sansReading: true)
    #expect(currentDisplay == s.expectedComposedText, "\(s.id) composed: got \(currentDisplay)")
    if let mustNotContain = s.expectedDisplayMustNotContain {
      #expect(!currentDisplay.contains(mustNotContain), "\(s.id) should not contain \(mustNotContain)")
    }
    switch s.id {
    case "IH408D":
      #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    default:
      #expect(!testHandler.mixedAlphanumericalBuffer.isEmpty)
    }
  }

  /// Trie validator must reject short English-looking tails such as `discordu6`.
  @Test
  func test_IH408F_MixedTrieValidatorKeepsInvalidEnglishTailRaw() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    defer { testHandler.clear() }

    typeSentence("discordu6")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer == "discordu6")
    #expect(testHandler.committableDisplayText(sansReading: true) == "discordu6")

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "discordu6")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
  }

  // MARK: Group B1 — Space Finalize: Terminal Suffix with Chinese Suffix

  private struct SpaceFinalizeTerminalSuffixScenario: Sendable {
    let id: String
    let input: String
    let expectedCommissions: [String]
    let expectedComposedText: String
  }

  @Test(arguments: [
    SpaceFinalizeTerminalSuffixScenario(
      id: "IH409A", input: "This5j; ",
      expectedCommissions: ["This"], expectedComposedText: "裝"
    ),
    SpaceFinalizeTerminalSuffixScenario(
      id: "IH409B", input: "this5j; ",
      expectedCommissions: ["this"], expectedComposedText: "裝"
    ),
  ])
  private func test_IH409_MixedSpaceFinalizeTerminalSuffix(_ s: SpaceFinalizeTerminalSuffixScenario) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    guard let gram = makeTemporaryGram(rawSequence: "5j; ", value: "裝", score: 999, using: testHandler) else {
      Issue.record("Failed to create gram for 5j; ")
      return
    }
    testHandler.currentLM.insertTemporaryData(unigram: gram, isFiltering: false)
    defer { testHandler.currentLM.clearTemporaryData(isFiltering: false); testHandler.clear() }

    typeSentence(s.input)

    #expect(testSession.recentCommissions == s.expectedCommissions, "\(s.id) commissions")
    #expect(testHandler.committableDisplayText(sansReading: true) == s.expectedComposedText, "\(s.id) composed")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
  }

  /// `acceptLeadingIntonations = false` 時，mixed mode 的聲調前置路徑應被封鎖。
  /// 大千排列下 `3su` = ˇ（前置）+ ㄋ + ㄧ = ㄋㄧˇ（你）；
  /// 啟用時應進入注音路徑（整段可發音），停用時應作為 ASCII 留在 buffer。
  @Test
  func test_IH410_MixedLeadingIntonationPrefDisabledBlocksToneFirstPhoneticPath() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }

    // 先推算 3su（聲調前置）的 reading key
    var composerNi3 = testHandler.composer
    composerNi3.clear()
    composerNi3.receiveSequence("3su", isRomaji: false)
    #expect(composerNi3.isPronounceable)
    #expect(composerNi3.hasIntonation())
    guard let readingKeyNi3 = composerNi3.phonabetKeyForQuery(pronounceableOnly: true) else {
      Issue.record("reading key for 3su (ㄋㄧˇ) is nil")
      return
    }

    testHandler.currentLM.insertTemporaryData(
      unigram: .init(keyArray: [readingKeyNi3], value: "你", score: -2),
      isFiltering: false
    )

    defer {
      testHandler.currentLM.clearTemporaryData(isFiltering: false)
      testHandler.clear()
      testHandler.prefs.acceptLeadingIntonations = true
    }

    // 案例 A：acceptLeadingIntonations = true（預設），3su 應觸發注音路徑，你 進組字器
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true
    testHandler.prefs.acceptLeadingIntonations = true

    typeSentence("3su")

    #expect(testHandler.committableDisplayText(sansReading: true) == "3su")
    #expect(testHandler.mixedInputSegmentStream.displayText == "3su")

    // 案例 B：acceptLeadingIntonations = false，3su 不得觸發注音路徑，應留在 ASCII buffer
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true
    testHandler.prefs.acceptLeadingIntonations = false

    typeSentence("3su")

    #expect(testHandler.mixedAlphanumericalBuffer == "3su")
    #expect(testHandler.committableDisplayText(sansReading: true) == "3su")

    // Enter 後應提交原始 ASCII
    _ = testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent)
    #expect(testSession.recentCommissions.contains("3su"))
  }

  // MARK: Group B2 — Space Finalize: Pure ASCII Word

  private struct SpaceFinalizeASCIIWordScenario: Sendable {
    let id: String
    let inputSequence: [String]
    let expectedCommission: String
  }

  @Test(arguments: [
    SpaceFinalizeASCIIWordScenario(
      id: "IH411A", inputSequence: ["tod "], expectedCommission: "tod "
    ),
    SpaceFinalizeASCIIWordScenario(
      id: "IH411B", inputSequence: ["film "], expectedCommission: "film "
    ),
    SpaceFinalizeASCIIWordScenario(
      id: "IH411C", inputSequence: ["What ", "the", " "], expectedCommission: "What the "
    ),
    SpaceFinalizeASCIIWordScenario(
      id: "IH411D", inputSequence: ["What the ", "hell", " "], expectedCommission: "What the hell "
    ),
  ])
  private func test_IH411_MixedSpaceFinalizeASCIIWord(_ s: SpaceFinalizeASCIIWordScenario) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    for step in s.inputSequence {
      typeSentence(step)
    }
    #expect(testSession.recentCommissions.joined() == s.expectedCommission, "\(s.id) commission")
    #expect(testHandler.committableDisplayText(sansReading: true).isEmpty, "\(s.id) composer should be empty")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty, "\(s.id) buffer should be empty")
  }

  /// 符號字元在 mixed mode 下應保留可見字面語義。
  @Test
  func test_IH412_MixedSymbolKeepsVisibleSemantics() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("!")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.generateStateOfInputting().displayedText == "！")

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "！")
  }

  /// 符號串在 mixed mode 下應維持 ASCII 提交，不得被誤導到注音路徑。
  @Test
  func test_IH413_MixedSymbolSequenceCommitsAsASCII() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("!@#$")

    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "！＠＃＄")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
  }

  /// 中英混輸後接符號，Enter 應提交中文 + ASCII（含符號）而不污染 composer。
  @Test
  func test_IH414_MixedEnterCommitsChinesePlusSymbolASCII() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    let testKanjiData = """
    ㄗㄚˊ 咱 -1
    ㄉㄜ˙ 地 -1
    """
    let extractedGrams = extractGrams(from: testKanjiData)
    extractedGrams.forEach {
      testHandler.currentLM.insertTemporaryData(unigram: $0, isFiltering: false)
    }
    defer {
      testHandler.currentLM.clearTemporaryData(isFiltering: false)
      testHandler.clear()
    }

    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    #expect(throws: Never.self) { try testHandler.assembler.insertKey("ㄗㄚˊ") }
    #expect(throws: Never.self) { try testHandler.assembler.insertKey("ㄉㄜ˙") }
    testSession.switchState(testHandler.generateStateOfInputting())

    typeSentence("!")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "咱地！")
  }

  /// 數字鍵與符號字元應保留不同語義（1 != !）。
  @Test
  func test_IH415_MixedDigitAndSymbolStayDistinct() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("1!")

    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "1！")
  }

  /// `=` 存在於 ASCII 前綴後，後續合法注音 suffix 仍應可走 terminal suffix commit。
  /// 鎖住目前符號與 suffix 互動結果，避免 raw buffer / punctuation 邊界回歸。
  @Test
  func test_IH416_MixedTerminalSuffixKeepsASCIIWithEqualsPrefix() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 擬 -1.5
    """
    let extractedGrams = extractGrams(from: testKanjiData)
    extractedGrams.forEach {
      testHandler.currentLM.insertTemporaryData(unigram: $0, isFiltering: false)
    }
    defer {
      testHandler.currentLM.clearTemporaryData(isFiltering: false)
      testHandler.clear()
    }

    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("Hello=")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    typeSentence("su3")
    #expect(testSession.recentCommissions.joined() == "Hello")
    #expect(testHandler.committableDisplayText(sansReading: true) == "＝你")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
  }

  /// US Keyboard + 大千下，`=` 在 mixed mode 應可保留標點語義。
  @Test
  func test_IH417_MixedEqualsKeyCommitsAsASCIIInUSDachenContext() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("a=")

    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.generateStateOfInputting().displayedText == "＝")
    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "a＝")
  }

  /// US Keyboard + 大千下，`\\` 在 mixed mode 應可保留標點語義。
  @Test
  func test_IH418_MixedBackslashKeyCommitsAsASCIIInUSDachenContext() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("a\\")

    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.generateStateOfInputting().displayedText == "、")
    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "a、")
  }

  /// ASCII 片段含 `=` / `\\` 時，mixed mode 提交結果應保持字面一致。
  @Test
  func test_IH419_MixedASCIIChunksWithEqualsAndBackslashStayLiteral() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("abc=def")
    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined().hasSuffix("abc＝def"))

    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("abc\\def")
    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined().hasSuffix("abc、def"))
  }

  // MARK: Group E — Option/Shift Orthogonal Paths

  private struct OptionShiftOrthogonalScenario: Sendable {
    let id: String
    let keyCode: UInt16
    let chars: String
    let charsSansModifiers: String
    let isOptionShift: Bool
    let expectedCommittedChar: String
    let needsDynamicLexiconInjection: Bool
    let halfWidthPunctuationEnabled: Bool?
  }

  @Test(arguments: [
    OptionShiftOrthogonalScenario(
      id: "IH420A", keyCode: 24, chars: "≠", charsSansModifiers: "=",
      isOptionShift: false, expectedCommittedChar: "=",
      needsDynamicLexiconInjection: true, halfWidthPunctuationEnabled: false
    ),
    OptionShiftOrthogonalScenario(
      id: "IH420B", keyCode: 18, chars: "¡", charsSansModifiers: "1",
      isOptionShift: false, expectedCommittedChar: "1",
      needsDynamicLexiconInjection: false, halfWidthPunctuationEnabled: .none
    ),
    OptionShiftOrthogonalScenario(
      id: "IH420C", keyCode: 0, chars: "Å", charsSansModifiers: "a",
      isOptionShift: true, expectedCommittedChar: "A",
      needsDynamicLexiconInjection: false, halfWidthPunctuationEnabled: .none
    ),
    OptionShiftOrthogonalScenario(
      id: "IH420D", keyCode: 44, chars: "¿", charsSansModifiers: "/",
      isOptionShift: true, expectedCommittedChar: "?",
      needsDynamicLexiconInjection: false, halfWidthPunctuationEnabled: false
    ),
  ])
  private func test_IH420_MixedOptionShiftOrthogonalPaths(_ s: OptionShiftOrthogonalScenario) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    if let hwPref = s.halfWidthPunctuationEnabled {
      testHandler.prefs.halfWidthPunctuationEnabled = hwPref
    }

    let event = KBEvent.KeyEventData(
      flags: s.isOptionShift ? [.option, .shift] : .option,
      chars: s.chars,
      charsSansModifiers: s.charsSansModifiers,
      keyCode: s.keyCode
    ).asEvent

    if s.needsDynamicLexiconInjection {
      let dynamicKeys = testHandler.punctuationQueryStrings(input: event)
      #expect(!dynamicKeys.isEmpty)
      let target = "〔Alt等號標點測試〕"
      let customGrams: [Homa.Gram] = dynamicKeys.map {
        .init(keyArray: [$0], value: target, score: 999)
      }
      customGrams.forEach {
        testHandler.currentLM.insertTemporaryData(unigram: $0, isFiltering: false)
      }
      #expect(dynamicKeys.contains { testHandler.currentLM.hasUnigramsFor(keyArray: [$0]) })
    }

    typeSentence("abc")

    #expect(event.isOptionHold)
    if s.isOptionShift {
      #expect(event.isShiftHold)
    }
    if s.id == "IH420B" {
      #expect(event.isMainAreaNumKey)
      #expect(event.mainAreaNumKeyChar == s.expectedCommittedChar)
    }

    #expect(testHandler.triageInput(event: event))
    #expect(testSession.recentCommissions == ["abc", s.expectedCommittedChar], "\(s.id) commissions")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testSession.state.type == .ofEmpty)

    if s.needsDynamicLexiconInjection {
      testHandler.currentLM.clearTemporaryData(isFiltering: false)
      testHandler.clear()
    }
  }

  /// 新規格：一般（無修飾鍵）標點 key 在詞庫有命中時，
  /// mixed mode 應依動態生成 key 判定為 CJK 標點輸入。
  @Test
  func test_IH421_MixedPlainPunctuationUsesDynamicLexiconKey() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    let target = "〔等號標點測試〕"
    let plainEqual = KBEvent.KeyEventData(chars: "=", keyCode: 24).asEvent
    let dynamicKeys = testHandler.punctuationQueryStrings(input: plainEqual)
    #expect(!dynamicKeys.isEmpty)
    let customGrams: [Homa.Gram] = dynamicKeys.map {
      .init(keyArray: [$0], value: target, score: 999)
    }
    customGrams.forEach {
      testHandler.currentLM.insertTemporaryData(unigram: $0, isFiltering: false)
    }
    #expect(dynamicKeys.contains { testHandler.currentLM.hasUnigramsFor(keyArray: [$0]) })
    defer {
      testHandler.currentLM.clearTemporaryData(isFiltering: false)
      testHandler.clear()
    }

    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true
    testHandler.prefs.halfWidthPunctuationEnabled = false

    typeSentence("abc")
    #expect(dynamicKeys.contains { testHandler.currentLM.hasUnigramsFor(keyArray: [$0]) })
    #expect(testHandler.triageInput(event: plainEqual))

    #expect(testSession.recentCommissions.joined() == "abc")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.committableDisplayText(sansReading: true) == target)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "abc" + target)
  }

  // MARK: Group D — CJK Punctuation vs. Phonetic Key

  private struct PunctuationVsPhoneticScenario: Sendable {
    let id: String
    let priorInput: String
    let keyCode: UInt16?
    let chars: String?
    let target: String?
    let expectedCommission: String
    let expectedComposedText: String
  }

  @Test(arguments: [
    PunctuationVsPhoneticScenario(
      id: "IH422A", priorInput: "z; ",
      keyCode: .none, chars: .none, target: .none,
      expectedCommission: "", expectedComposedText: "芳"
    ),
    PunctuationVsPhoneticScenario(
      id: "IH422B", priorInput: "abc",
      keyCode: 33, chars: "[", target: "「",
      expectedCommission: "abc", expectedComposedText: "「"
    ),
    PunctuationVsPhoneticScenario(
      id: "IH422C", priorInput: "abc",
      keyCode: 30, chars: "]", target: "」",
      expectedCommission: "abc", expectedComposedText: "」"
    ),
  ])
  private func test_IH422_MixedPunctuationVsPhoneticKey(_ s: PunctuationVsPhoneticScenario) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()

    if s.id == "IH422A" {
      _ = injectTemporaryGrams(testHandler, "ㄈㄤ 芳 -1")
    } else if let target = s.target, let keyCode = s.keyCode, let chars = s.chars {
      let event = KBEvent.KeyEventData(chars: chars, keyCode: keyCode).asEvent
      let dynamicKeys = testHandler.punctuationQueryStrings(input: event)
      #expect(!dynamicKeys.isEmpty)
      let customGrams: [Homa.Gram] = dynamicKeys.map {
        .init(keyArray: [$0], value: target, score: 999)
      }
      customGrams.forEach {
        testHandler.currentLM.insertTemporaryData(unigram: $0, isFiltering: false)
      }
    }

    typeSentence(s.priorInput)

    if let keyCode = s.keyCode, let chars = s.chars {
      let event = KBEvent.KeyEventData(chars: chars, keyCode: keyCode).asEvent
      #expect(testHandler.triageInput(event: event), "\(s.id) punctuation should be handled")
    }

    #expect(testSession.recentCommissions.joined() == s.expectedCommission, "\(s.id) commission")
    if s.id == "IH422A" {
      #expect(testSession.state.displayedText == s.expectedComposedText, "\(s.id) displayedText")
    } else {
      #expect(testHandler.committableDisplayText(sansReading: true) == s.expectedComposedText, "\(s.id) composed")
    }
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    if s.keyCode != nil {
      #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
      #expect(
        testSession.recentCommissions.joined() == s.expectedCommission + s.expectedComposedText,
        "\(s.id) after Enter"
      )
    }

    testHandler.currentLM.clearTemporaryData(isFiltering: false)
    testHandler.clear()
  }

  /// symbol menu physical key 不得被 mixed handler 攔截。
  /// 當 mixed 緩衝非空時，應先提交全部內容，再落入符號選單分流。
  @Test
  func test_IH423_MixedSymbolMenuPhysicalKeyFlushesThenFallsThroughToMenu() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("abc")
    #expect(testHandler.mixedAlphanumericalBuffer == "abc")

    let symbolMenuEvent = KBEvent.KeyEventData.symbolMenuKeyEventIntl.asEvent
    #expect(symbolMenuEvent.isSymbolMenuPhysicalKey)
    #expect(testHandler.triageInput(event: symbolMenuEvent))

    #expect(testSession.recentCommissions.joined() == "abc")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testSession.state.type == .ofSymbolTable)
  }

  /// 若 key event 只帶 base glyph（`/`）但同時有 Shift，
  /// mixed mode 應仍保留可見語義 `?`，不得退化成 `/`。
  @Test
  func test_IH424_MixedShiftSlashKeepsQuestionMarkVisibleSemantics() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentence("What")
    let shiftSlash = KBEvent.KeyEventData(
      flags: .shift,
      chars: "/",
      charsSansModifiers: "/",
      keyCode: 44
    ).asEvent
    #expect(shiftSlash.isShiftHold)
    #expect(shiftSlash.text == "/")
    #expect(shiftSlash.inputTextIgnoringModifiers == "/")

    #expect(testHandler.triageInput(event: shiftSlash))
    #expect(testHandler.mixedAlphanumericalBuffer == "What?")
    #expect(!testHandler.mixedAlphanumericalBuffer.hasSuffix("/"))

    let displayed = testHandler.generateStateOfInputting().displayedText
    #expect(displayed.hasSuffix("?") || displayed.hasSuffix("？"))

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    let commissioned = testSession.recentCommissions.joined()
    #expect(!commissioned.contains("What/"))
    #expect(commissioned.contains("What?") || commissioned.contains("What？"))
  }

  // MARK: - Fileprivate Helpers.

  fileprivate func prepareMixedModeHandler() throws -> (handler: MockInputHandler, session: MockSession) {
    guard let testHandler, let testSession else {
      struct MissingTestFixture: Error {}
      Issue.record("testHandler and testSession at least one of them is nil.")
      throw MissingTestFixture()
    }
    testHandler.clear()
    testSession.resetInputHandler(forceComposerCleanup: true)
    testHandler.prefs.mixedAlphanumericalEnabled = true
    return (testHandler, testSession)
  }

  fileprivate func injectTemporaryGrams(_ handler: MockInputHandler, _ kanjiData: String) -> (() -> ()) {
    let extractedGrams = extractGrams(from: kanjiData)
    extractedGrams.forEach {
      handler.currentLM.insertTemporaryData(unigram: $0, isFiltering: false)
    }
    return { handler.currentLM.clearTemporaryData(isFiltering: false) }
  }

  /// Helper to build a temporary gram from a raw phonabet sequence using the handler's composer config.
  fileprivate func makeTemporaryGram(
    rawSequence: String, value: String, score: Double, using handler: MockInputHandler
  )
    -> Homa.Gram? {
    var composer = handler.composer
    composer.clear()
    composer.receiveSequence(rawSequence, isRomaji: false)
    guard composer.isPronounceable, composer.hasIntonation() else { return nil }
    guard let key = composer.phonabetKeyForQuery(
      pronounceableOnly: handler.prefs.acceptLeadingIntonations
    ) else { return nil }
    return .init(keyArray: [key], value: value, score: score)
  }
}
