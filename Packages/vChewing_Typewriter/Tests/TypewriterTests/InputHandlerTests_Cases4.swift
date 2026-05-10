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

  /// IH404B: `filterStandalonePhonabetInMixedAlphanumerical` gate 必須區分
  /// 「LM bestCandidate == reading 自己（如 ㄅ→ㄅ）」與「LM 有真漢字（如 ㄕ→詩）」。
  /// Preference ON：前者擋成 raw、後者放行 commit 漢字。
  /// Preference OFF：兩者皆 commit。
  @Test
  func test_IH404B_FilterStandalonePhonabetInMixedAlphanumericalGate() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    // 模擬 production LM：
    //   ㄅ / ㄉ：LM 只能 fall back 回 reading 自己（注入「ㄅ ㄅ」「ㄉ ㄉ」）。
    //   ㄕ / ㄓ：LM 有真漢字（注入「ㄕ 詩」「ㄓ 之」）。
    let testKanjiData = """
    ㄅ ㄅ -1
    ㄉ ㄉ -1
    ㄕ 詩 -1
    ㄓ 之 -1
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    struct Case { let input: String; let onExpect: String; let offExpect: String }
    let cases: [Case] = [
      .init(input: "1 ", onExpect: "1 ", offExpect: "ㄅ"),  // LM fallback → 擋
      .init(input: "2 ", onExpect: "2 ", offExpect: "ㄉ"),  // LM fallback → 擋
      .init(input: "g ", onExpect: "詩", offExpect: "詩"),  // 真漢字 → 不擋
      .init(input: "5 ", onExpect: "之", offExpect: "之"),  // 真漢字 → 不擋
    ]

    for prefOn in [true, false] {
      testHandler.prefs.filterStandalonePhonabetInMixedAlphanumerical = prefOn
      for c in cases {
        testHandler.clear()
        testSession.recentCommissions.removeAll()
        typeSentence(c.input)
        _ = testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent)
        let commissioned = testSession.recentCommissions.joined()
        let expected = prefOn ? c.onExpect : c.offExpect
        #expect(
          commissioned == expected,
          "Preference \(prefOn ? "ON" : "OFF") 時 \(c.input.debugDescription) 應 commit \(expected.debugDescription)，但得到 \(commissioned.debugDescription)"
        )
      }
    }
    testHandler.prefs.filterStandalonePhonabetInMixedAlphanumerical = true
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

  /// Single ASCII raw segment followed by a dead-restarted Dachen syllable must split into
  /// raw("Y") + chinese("軸"), not keep the whole `Y5.6` raw nor scan suffixes afterward.
  @Test
  func test_IH405D_MixedAlnumDeadRestartSingleAsciiBeforeZhuyinTail() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄓㄡˊ 軸 -1
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("Y5.6")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .raw("Y"),
      .chinese(text: "軸", readings: ["ㄓㄡˊ"]),
    ])
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.committableDisplayText(sansReading: true) == "Y軸")
  }

  /// Repeated ASCII key followed by a valid Zhuyin tail should be resolved by
  /// active-suffix replacement, not by any ASCII-prefix workaround policy.
  @Test
  func test_IH405D_MixedAlnumRepeatedAsciiThenZhuyinTailUsesActiveSuffix() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄌㄧㄠˇ 了 -1
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("xxul3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .raw("x"),
      .chinese(text: "了", readings: ["ㄌㄧㄠˇ"]),
    ])
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.committableDisplayText(sansReading: true) == "x了")
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
    #expect(testHandler.mixedInputSegmentStream.rawTextSegments == [expectedASCIIPrefix])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    typeSentence("cl3")

    let composedText = testHandler.committableDisplayText(sansReading: true)
    #expect(!composedText.isEmpty)
    #expect(composedText == expectedASCIIPrefix + "你好")
    #expect(testHandler.generateStateOfInputting().displayedText == expectedASCIIPrefix + "你好")
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.rawTextSegments == [expectedASCIIPrefix])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == expectedASCIIPrefix + "你好")
  }


  /// Candidate selection in a mixed stream must not resurrect a stale raw tail.
  /// Regression: typing `你好test你`, selecting the trailing `你`, then pressing Enter
  /// committed `你好test你test` because candidate confirmation restored the pre-selection
  /// cursor while leaving `mixedAlphanumericalBuffer` stale as `test`; the next inputting
  /// state appended that stale buffer back into the segment stream.
  @Test
  func test_IH433_MixedCandidateSelectionDoesNotResurrectStaleRawTail() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 妳 -1.5
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3cl3testsu3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.displayText == "你好test你")
    #expect(testHandler.mixedInputSegmentStream.rawTextSegments == ["test"])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataArrowDown.asEvent))
    let candidates = testSession.state.candidates.map(\.value)
    #expect(candidates.contains("妳"))
    let targetIndex = candidates.firstIndex(of: "妳") ?? 0
    testSession.candidatePairSelectionConfirmed(at: targetIndex)

    #expect(testHandler.mixedInputSegmentStream.displayText == "你好test妳")
    #expect(testHandler.mixedInputSegmentStream.rawTextSegments == ["test"])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testSession.state.displayedText == "你好test妳")

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "你好test妳")
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
    #expect(testHandler.mixedInputSegmentStream.rawTextSegments == ["test"])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
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
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    if let followUp = s.followUpInput, let expectedAfter = s.expectedComposedTextAfterFollowUp {
      typeSentence(followUp)
      #expect(testSession.recentCommissions == s.expectedCommissions, "\(s.id) commissions after follow-up")
      #expect(
        testHandler.committableDisplayText(sansReading: true) == expectedAfter,
        "\(s.id) composed after follow-up"
      )
      #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
      #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
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
    TerminalSuffixBoundaryScenario(
      id: "IH408G", input: "ru.4",
      expectedCommissions: [], expectedComposedText: "就",
      expectedDisplayMustNotContain: "ru.4",
      gramSpecs: [
        GramSpec(rawSequence: "ru.4", value: "就", score: 999),
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
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
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
      expectedCommissions: [], expectedComposedText: "This裝"
    ),
    SpaceFinalizeTerminalSuffixScenario(
      id: "IH409B", input: "this5j; ",
      expectedCommissions: [], expectedComposedText: "this裝"
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
  }

  @Test(arguments: [
    SpaceFinalizeTerminalSuffixScenario(
      id: "IH409C", input: "g ",
      expectedCommissions: [], expectedComposedText: "詩"
    ),
    SpaceFinalizeTerminalSuffixScenario(
      id: "IH409D", input: "n ",
      expectedCommissions: [], expectedComposedText: "司"
    ),
    SpaceFinalizeTerminalSuffixScenario(
      id: "IH409E", input: "t ",
      expectedCommissions: [], expectedComposedText: "吃"
    ),
  ])
  private func test_IH409B_MixedBareConsonantFirstToneStaysInTrie(_ s: SpaceFinalizeTerminalSuffixScenario) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let rawSequence = s.input
    guard let gram = makeTemporaryGram(rawSequence: rawSequence, value: s.expectedComposedText, score: 999, using: testHandler) else {
      Issue.record("Failed to create gram for \(rawSequence)")
      return
    }
    testHandler.currentLM.insertTemporaryData(unigram: gram, isFiltering: false)
    defer { testHandler.currentLM.clearTemporaryData(isFiltering: false); testHandler.clear() }

    typeSentence(s.input)

    #expect(testSession.recentCommissions == s.expectedCommissions, "\(s.id) commissions")
    #expect(testHandler.committableDisplayText(sansReading: true) == s.expectedComposedText, "\(s.id) composed")
    #expect(testHandler.mixedInputSegmentStream.displayText == s.expectedComposedText, "\(s.id) stream")
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

  private struct SpaceAsRawASCIIScenario: Sendable {
    let id: String
    let inputSequence: [String]
    let expectedComposition: String
  }

  @Test(arguments: [
    SpaceAsRawASCIIScenario(
      id: "IH411A", inputSequence: ["tod "], expectedComposition: "tod "
    ),
    SpaceAsRawASCIIScenario(
      id: "IH411B", inputSequence: ["film "], expectedComposition: "film "
    ),
    SpaceAsRawASCIIScenario(
      id: "IH411C", inputSequence: ["What ", "the", " "], expectedComposition: "What the "
    ),
    SpaceAsRawASCIIScenario(
      id: "IH411D", inputSequence: ["What the ", "hell", " "], expectedComposition: "What the hell "
    ),
    SpaceAsRawASCIIScenario(
      id: "IH411E", inputSequence: ["That was ", "woo", " "], expectedComposition: "That was woo "
    ),
  ])
  private func test_IH411_MixedSpaceStaysInRawASCIIStream(_ s: SpaceAsRawASCIIScenario) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    for step in s.inputSequence {
      typeSentence(step)
    }
    #expect(testSession.recentCommissions.isEmpty, "\(s.id) no implicit commission")
    #expect(testHandler.committableDisplayText(sansReading: true) == s.expectedComposition, "\(s.id) composition")
    #expect(testHandler.mixedInputSegmentStream.displayText == s.expectedComposition, "\(s.id) stream remains editable")
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

  /// mixed segment stream 已接管顯示來源時，Down/翻頁等明確候選鍵仍應能進入選字窗；
  /// 不可因 assembler 為空或 active raw tail 非空而被候選窗入口擋掉。
  @Test(arguments: [
    ("IH411A", 125, "\u{F701}"),
  ])
  func test_IH411_MixedSegmentStreamArrowKeyCanOpenCandidateWindow(
    id: String,
    keyCode: Int,
    chars: String
  ) throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3cl3test")

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你好test")
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test")
    #expect(!testHandler.mixedInputSegmentStream.isEmpty)

    let eventData = KBEvent.KeyEventData(chars: chars, keyCode: UInt16(keyCode))
    #expect(testHandler.triageInput(event: eventData.asEvent), "\(id) triage")
    #expect(testSession.state.type == .ofCandidates, "\(id) state")
    #expect(testSession.state.displayedText == "你好test", "\(id) display")
  }

  /// mixed stream 內 bare Left/Right 是組字游標移動，不是候選窗入口；
  /// 游標移動後再用 Down 叫候選窗，應針對游標所在的中文 segment 顯示/選字。
  @Test
  func test_IH411B_MixedSegmentStreamBareLeftRightMovesCompositionCursorBeforeCandidateWindow() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 妳 -2
    ㄋㄧˇ 擬 -3
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3testsu3")

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你test你")
    #expect(testHandler.assembler.cursor == 2)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataArrowLeft.asEvent))
    #expect(testSession.state.type == .ofInputting)
    #expect(testHandler.assembler.cursor == 1)
    #expect(testSession.state.cursor == 1)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataArrowRight.asEvent))
    #expect(testSession.state.type == .ofInputting)
    #expect(testHandler.assembler.cursor == 2)
    #expect(testSession.state.cursor == "你test你".count)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataArrowDown.asEvent))
    #expect(testSession.state.type == .ofCandidates)
    guard let targetIndex = testSession.state.candidates.firstIndex(where: { $0.value == "妳" }) else {
      Issue.record("Expected candidate 妳 to exist among: \(testSession.state.candidates.map(\.value))")
      return
    }
    testSession.candidatePairSelectionConfirmed(at: targetIndex)

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你test妳")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你", "test", "妳"])
  }

  /// mixed segment stream 作為顯示 source of truth 時，候選窗選字後也必須只改被選候選的讀音範圍；
  /// 不可用 Homa retokenized smashedPairs 整段回寫 stream，否則會在「你好test你」這類 raw boundary
  /// 場景把前段中文依照純 Homa 序列重鋪，造成後綴重複或錯位。
  @Test
  func test_IH412_MixedSegmentStreamCandidateSelectionUpdatesOnlySelectedRange() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 妳 -2
    ㄋㄧˇ 擬 -3
    ㄏㄠˇ 好 -1
    ㄏㄠˇ 郝 -2
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3cl3testsu3")

    #expect(testSession.state.displayedText == "你好test你")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你好", "test", "你"])
    #expect(!testHandler.mixedInputSegmentStream.isEmpty)

    testSession.switchState(testHandler.generateStateOfCandidates())
    let values = testSession.state.candidates.map(\.value)
    #expect(!values.contains("郝"), "tail cursor must not expose candidate from the prefix Chinese segment: \(values)")

    testHandler.assembler.cursor = 2
    testSession.switchState(testHandler.generateStateOfCandidates())
    guard let targetIndex = testSession.state.candidates.firstIndex(where: { $0.value == "郝" }) else {
      Issue.record("Expected candidate 郝 to exist among: \(testSession.state.candidates.map(\.value))")
      return
    }

    testSession.candidatePairSelectionConfirmed(at: targetIndex)

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你郝test你")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你郝", "test", "你"])
    #expect(testHandler.committableDisplayText(sansReading: true) == "你郝test你")
  }

  /// mixed stream 內若同一讀音出現在 raw boundary 兩側，Left/Right 移動 Homa 游標後
  /// confirm 必須依游標所在的 Chinese segment 改字；不能永遠替換第一個 matching keyArray。
  @Test
  func test_IH412B_MixedSegmentStreamCandidateSelectionRespectsCursorAcrossRawBoundary() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 妳 -2
    ㄋㄧˇ 擬 -3
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3testsu3")

    #expect(testSession.state.displayedText == "你test你")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你", "test", "你"])
    #expect(!testHandler.mixedInputSegmentStream.isEmpty)

    testHandler.assembler.cursor = 2
    testSession.switchState(testHandler.generateStateOfCandidates())
    guard let targetIndex = testSession.state.candidates.firstIndex(where: { $0.value == "妳" }) else {
      Issue.record("Expected candidate 妳 to exist among: \(testSession.state.candidates.map(\.value))")
      return
    }

    testSession.candidatePairSelectionConfirmed(at: targetIndex)

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你test妳")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你", "test", "妳"])
    #expect(testHandler.committableDisplayText(sansReading: true) == "你test妳")
  }

  @Test
  func test_IH431_MixedSegmentStreamCandidatePreviewPreservesMiddleRawAfterSingleChinesePrefix() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄏㄠˇ 好 -1
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 妳 -2
    ㄏㄠˇ-ㄋㄧˇ 好你 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("cl3testsu3")

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "好test你")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["好", "test", "你"])
    #expect(testHandler.assembler.cursor == 2)

    testSession.switchState(testHandler.generateStateOfCandidates())
    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "好test你")
    #expect(testSession.state.displayTextSegments == ["好", "test", "你"])
    #expect(testSession.state.cursor == "好test你".count)

    guard let initialIndex = testSession.state.candidates.firstIndex(where: { $0.value == "你" }) else {
      Issue.record("Expected candidate 你 to exist among: \(testSession.state.candidates.map(\.value))")
      return
    }
    testSession.candidatePairHighlightChanged(at: initialIndex)

    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "好test你")
    #expect(testSession.state.displayTextSegments == ["好", "test", "你"])
    #expect(testSession.state.cursor == "好test你".count)

    testSession.state.highlightedCandidateIndex = nil
    guard let targetIndex = testSession.state.candidates.firstIndex(where: { $0.value == "妳" }) else {
      Issue.record("Expected candidate 妳 to exist among: \(testSession.state.candidates.map(\.value))")
      return
    }
    testSession.candidatePairHighlightChanged(at: targetIndex)

    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "好test妳")
    #expect(testSession.state.displayTextSegments == ["好", "test", "妳"])
    #expect(testSession.state.cursor == "好test妳".count)
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["好", "test", "你"])
  }

  @Test
  func test_IH432_MixedSegmentStreamCandidateAbortCommitsMiddleRawAfterPreview() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄏㄠˇ 郝 -2
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3cl3testcl3")

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你好test好")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你好", "test", "好"])

    testSession.switchState(testHandler.generateStateOfCandidates())
    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "你好test好")

    guard let targetIndex = testSession.state.candidates.firstIndex(where: { $0.value == "郝" }) else {
      Issue.record("Expected candidate 郝 to exist among: \(testSession.state.candidates.map(\.value))")
      return
    }
    testSession.candidatePairHighlightChanged(at: targetIndex)

    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "你好test郝")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你好", "test", "好"])

    testSession.switchState(.ofEmpty())

    #expect(testSession.recentCommissions.joined() == "你好test好")
    #expect(testSession.state.type == .ofEmpty)
  }

  /// `你好test好` 是皇上實機回報的 mixed boundary 選字案例：
  /// 游標在尾端中文、前面隔著 raw segment 時，Down 應能開候選窗、選到尾端 `好` 的候選，
  /// confirm 後不可跳回 raw boundary，也不可把 `test` 重複復活。
  @Test
  func test_IH435_MixedStackBufferCanSelectTrailingChineseAfterMiddleRaw() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄏㄠˇ 郝 -2
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3cl3testcl3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你好test好")
    #expect(testSession.state.cursor == "你好test好".count)
    #expect(testHandler.assembler.cursor == testHandler.mixedInputSegmentStream.readingCount)
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你好", "test", "好"])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataArrowDown.asEvent))
    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "你好test好")
    #expect(testSession.state.cursor == "你好test好".count)

    guard let targetIndex = testSession.state.candidates.firstIndex(where: { $0.value == "郝" }) else {
      Issue.record("Expected candidate 郝 for trailing 好 among: \(testSession.state.candidates.map(\.value))")
      return
    }

    testSession.candidatePairHighlightChanged(at: targetIndex)
    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "你好test郝")
    #expect(testSession.state.displayTextSegments == ["你好", "test", "郝"])
    #expect(testSession.state.cursor == "你好test郝".count)
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你好", "test", "好"])

    testSession.candidatePairSelectionConfirmed(at: targetIndex)
    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你好test郝")
    #expect(testSession.state.cursor == "你好test郝".count)
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你好", "test", "郝"])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "你好test郝")
  }

  /// 皇上實機回報：長 buffer 到「後由標」附近時，視覺上對著「標」叫選字，
  /// 候選內容不可漂移到前面的「由」或「後由」。此測試刻意把「標」與「由」
  /// 的候選做成可辨識語義，並從尾端用 Left 移到「標」後方再開候選窗。
  @Test
  func test_IH436_LongMixedBufferCandidateAnchorStaysOnBiaoInsteadOfYou() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄉㄠˋ 到 -1
    ㄧˊ 一 -1
    ㄉㄧㄥˋ 定 -1
    ㄕㄨˋ 數 -1
    ㄌㄧㄤˋ 量 -1
    ㄏㄡˋ 後 -1
    ㄧㄡˊ 由 -1
    ㄧㄡˊ 油 -2
    ㄅㄧㄠ 標 -1
    ㄅㄧㄠ 錶 -2
    ㄐㄧㄡˋ 就 -1
    ㄘㄨㄛˋ 錯 -1
    ㄌㄜ˙ 了 -1
    ㄋㄜ˙ 呢 -1
    ㄏㄡˋ-ㄧㄡˊ 後由 -3
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    let readings = [
      "ㄉㄠˋ", "ㄧˊ", "ㄉㄧㄥˋ", "ㄕㄨˋ", "ㄌㄧㄤˋ", "ㄏㄡˋ", "ㄧㄡˊ", "ㄅㄧㄠ",
      "ㄐㄧㄡˋ", "ㄘㄨㄛˋ", "ㄌㄜ˙", "ㄋㄜ˙",
    ]
    for key in readings {
      #expect(throws: Never.self) { try testHandler.assembler.insertKey(key) }
    }
    testHandler.mixedInputSegmentStream.appendChinese(
      text: "到一定數量後由標就錯了呢",
      readings: readings
    )
    testHandler.mixedInputRawBuffer = testHandler.mixedInputSegmentStream.activeRawBuffer
    testHandler.mixedAlphanumericalBuffer = testHandler.mixedInputSegmentStream.activeRawText
    testSession.switchState(testHandler.generateStateOfInputting())

    #expect(testSession.state.displayedText == "到一定數量後由標就錯了呢")
    #expect(testHandler.assembler.cursor == readings.count)
    #expect(testSession.state.cursor == "到一定數量後由標就錯了呢".count)

    for _ in 0 ..< 4 {
      #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataArrowLeft.asEvent))
    }
    #expect(testHandler.assembler.cursor == 8)
    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.cursor == "到一定數量後由標".count)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataArrowDown.asEvent))
    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "到一定數量後由標就錯了呢")
    #expect(testSession.state.cursor == "到一定數量後由標".count)

    let candidates = testSession.state.candidates
    let values = candidates.map(\.value)
    let keyArrays = candidates.map(\.keyArray)
    #expect(values.contains("錶"), "候選窗應針對『標/ㄅㄧㄠ』，實際候選：\(candidates)")
    #expect(keyArrays.allSatisfy { $0 == ["ㄅㄧㄠ"] }, "候選 anchor 不可漂移到『由』或『後由』：\(candidates)")
    #expect(!values.contains("油"), "候選窗漂移到『由/ㄧㄡˊ』：\(candidates)")
    #expect(!values.contains("後由"), "候選窗跨到『後由/ㄏㄡˋ-ㄧㄡˊ』：\(candidates)")
  }

  @Test
  func test_IH430_MixedSegmentStreamCandidatePreviewPreservesRawBoundaryDisplay() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 妳 -2
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    ㄋㄧˇ-ㄏㄠˇ 旎好 -3
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3testsu3cl3")

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你test你好")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你", "test", "你好"])
    #expect(testHandler.assembler.cursor == 3)

    testSession.switchState(testHandler.generateStateOfCandidates())
    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "你test你好")
    #expect(testSession.state.displayTextSegments == ["你", "test", "你好"])
    #expect(testSession.state.cursor == "你test你好".count)

    guard let targetIndex = testSession.state.candidates.firstIndex(where: { $0.value == "旎好" }) else {
      Issue.record("Expected candidate 旎好 to exist among: \(testSession.state.candidates.map(\.value))")
      return
    }
    testSession.candidatePairHighlightChanged(at: targetIndex)

    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == "你test旎好")
    #expect(testSession.state.displayTextSegments == ["你", "test", "旎好"])
    #expect(testSession.state.cursor == "你test旎好".count)
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你", "test", "你好"])
  }

  @Test
  func test_IH429_MixedSegmentStreamInputtingCursorStaysAfterActiveRawTail() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3cl3test")

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你好test")
    #expect(testHandler.assembler.cursor == testHandler.mixedInputSegmentStream.readingCount)
    #expect(testHandler.mixedInputSegmentStream.activeRawText == "test")
    #expect(testSession.state.cursor == "你好test".count)
    #expect(testHandler.generateStateOfInputting().cursor == "你好test".count)
  }

  /// mixed segment stream 的 raw segment 是硬邊界；`你test你` 進候選窗時，不可把前後兩個 `你`
  /// 合併成同一個雙音節候選（例如候選列出 `倪倪`/`薿薿`），否則選字會一次改掉兩邊。
  @Test
  func test_IH413_MixedSegmentStreamCandidateListDoesNotCrossRawSegmentBoundary() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 妳 -2
    ㄋㄧˇ 擬 -3
    ㄋㄧˇ-ㄋㄧˇ 倪倪 -4
    ㄋㄧˇ-ㄋㄧˇ 薿薿 -5
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3testsu3")

    #expect(testSession.state.displayedText == "你test你")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你", "test", "你"])

    testSession.switchState(testHandler.generateStateOfCandidates())
    #expect(testSession.state.type == .ofCandidates)

    let values = testSession.state.candidates.map(\.value)
    #expect(values.contains("妳") || values.contains("擬"))
    #expect(!values.contains("倪倪"))
    #expect(!values.contains("薿薿"))
    #expect(values.allSatisfy { $0.count <= 1 }, "Candidate list crossed raw segment boundary: \(values)")
  }

  /// 含 active raw reading + 已提交 mixed Chinese 時，Enter 不可把 raw tail 當裸注音一起提交。
  /// Regression: live 顯示 `ㄋㄋㄟㄋㄟ你` 後 Enter，曾把 `ㄋㄋㄟㄋㄟ` 連同 `你` 一起提交。
  @Test
  func test_IH438_MixedEnterWithIncompleteReadingAndChineseSegmentCommitsOnlyStreamText() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    defer { testHandler.clear() }

    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄟ-ㄋㄟ ㄋㄟㄋㄟ -1
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup() }

    typeSentence("su3ssoo")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
      .raw("ssoo"),
    ])
    #expect(testSession.state.displayedText == "你ssoo")
    #expect(testHandler.assembler.length == 1)
    #expect(testHandler.assembler.cursor == 1)
    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "你ssoo")
  }

  /// leading raw Space + Chinese 的 Backspace 不可把 stream/Homa 拆成殘留注音 tooltip。
  /// Regression: live `" 你好"` 後按 Backspace，畫面殘留 `ㄋ|`，代表 stream 刪字與 assembler / cursor sync 分裂。
  @Test
  func test_IH437_MixedLeadingSpaceBackspaceKeepsChineseSegmentSynced() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    defer { testHandler.clear() }

    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup() }

    typeSentence(" su3cl3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .raw(" "),
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
    ])
    #expect(testSession.state.displayedText == " 你好")
    #expect(testSession.state.tooltip.isEmpty)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.backspace.asEvent))

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .raw(" "),
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
    ])
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.mixedInputRawBuffer.rawBuffer.isEmpty)
    #expect(testHandler.assembler.length == 1)
    #expect(testHandler.assembler.cursor == 1)
    #expect(testSession.state.displayedText == " 你")
    #expect(testSession.state.tooltip.isEmpty)
  }

  /// 已有中文 + raw tail，Backspace 刪空 raw tail 後再輸入中文，應回到相鄰 Chinese segment 合併；
  /// 不可留下 `[chinese("你好"), chinese("好")]` 這種未正規化 stack。
  @Test
  func test_IH426_MixedBackspaceClearsRawTailThenNextChineseMergesWithPreviousChineseSegment() throws {
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
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      .raw("test"),
    ])
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test")

    for _ in 0 ..< 4 {
      #expect(testHandler.triageInput(event: KBEvent.KeyEventData.backspace.asEvent))
    }

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
    ])
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好")

    typeSentence("cl3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好好", readings: ["ㄋㄧˇ", "ㄏㄠˇ", "ㄏㄠˇ"]),
    ])
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好好")
    #expect(testHandler.generateStateOfInputting().displayedText == "你好好")
  }

  /// mixed stream 刪除尾端中文時，Backspace 不只要改 stream，也要同步 Homa assembler；
  /// 否則畫面看似刪掉尾字，下一次 terminal suffix commit / candidate 會讀到 stale reading cursor。
  @Test
  func test_IH427_MixedBackspaceDeletingChineseTailSyncsAssemblerBeforeNextInput() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    defer { testHandler.clear() }

    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup() }

    typeSentence("su3cl3testsu3")
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      .raw("test"),
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
    ])
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test你")

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.backspace.asEvent))

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      .raw("test"),
    ])
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test")

    typeSentence("cl3")

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      .raw("test"),
      .chinese(text: "好", readings: ["ㄏㄠˇ"]),
    ])
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test好")
    #expect(testHandler.assembler.length == 3)
  }

  /// 游標移到 mixed stream 中間時，Backspace 應刪除游標前一個 Chinese reading，
  /// 不可忽略 cursor 而刪掉尾端 segment。
  @Test
  func test_IH428_MixedBackspaceRespectsReadingCursorInsideChineseSegments() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    defer { testHandler.clear() }

    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup() }

    typeSentence("su3cl3testsu3")
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test你")

    testHandler.assembler.cursor = 2
    testSession.switchState(testHandler.generateStateOfInputting())
    #expect(testSession.state.cursor == 2)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.backspace.asEvent))

    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
      .raw("test"),
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
    ])
    #expect(testHandler.committableDisplayText(sansReading: true) == "你test你")
    #expect(testHandler.assembler.length == 2)
  }

  /// raw→中文的 terminal suffix match 必須是 stack tail pop/replace：
  /// `[中文("你好"), raw("testsu3")] -> [中文("你好"), raw("test"), 中文("你")]`。
  /// 尾端 raw 被替換後，compat buffer 不得回填成上一個 raw segment，否則 Enter/commit 會把 `test` 再輸出一次。
  @Test
  func test_IH414_MixedTerminalSuffixCommitPopsOnlyTailRawAndDoesNotDuplicateRawOnEnter() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -2
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("su3cl3testsu3")

    #expect(testSession.state.displayedText == "你好test你")
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你好", "test", "你"])
    #expect(testHandler.mixedInputSegmentStream.rawTextSegments == ["test"])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test你")

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent))
    #expect(testSession.recentCommissions.joined() == "你好test你")
    #expect(testHandler.mixedInputSegmentStream.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
  }

  /// Space 是大千一聲鍵；mixed mode normal typing 不可把 Space 當 finalize commit。
  /// Regression: after raw tail has already been converted to Chinese, `mixedAlphanumericalBuffer`
  /// is empty while `mixedInputSegmentStream` still contains composition. Space must still route to
  /// MixedAlphanumericalTypewriter instead of legacy Space commit path.
  @Test
  func test_IH425_MixedSpaceToneDoesNotCommitSegmentStream() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄓ 之 -1
    ㄋㄧˇ 你 -1
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("5")
    #expect(testHandler.triageInput(event: KBEvent.KeyEventData(chars: " ", keyCode: KeyCode.kSpace.rawValue).asEvent))
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.displayText == "之")
    #expect(testHandler.generateStateOfInputting().displayedText == "之")

    typeSentence("su3")
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.displayText == "之你")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    #expect(testHandler.triageInput(event: KBEvent.KeyEventData(chars: " ", keyCode: KeyCode.kSpace.rawValue).asEvent))
    #expect(testSession.recentCommissions.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.displayText == "之你 ")
    #expect(testHandler.generateStateOfInputting().displayedText == "之你 ")
  }

  @Test
  func test_IH434_MixedCandidatePreviewDoesNotDuplicateRawBoundaryTail() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    let testKanjiData = """
    ㄋㄢˊ 南 -1
    ㄋㄢˊ 難 -0.5
    ㄕㄥ 生 -1
    ㄅㄧˋ 必 -1
    ㄇㄞˇ 買 -1
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); testHandler.clear() }

    typeSentence("themall")
    #expect(testHandler.mixedInputSegmentStream.displayText == "themall")
    #expect(testHandler.mixedAlphanumericalBuffer == "themall")

    for key in ["ㄋㄢˊ", "ㄕㄥ", "ㄅㄧˋ", "ㄇㄞˇ"] {
      #expect(throws: Never.self) { try testHandler.assembler.insertKey(key) }
    }
    testHandler.mixedInputSegmentStream.appendChinese(
      text: "南生必買",
      readings: ["ㄋㄢˊ", "ㄕㄥ", "ㄅㄧˋ", "ㄇㄞˇ"]
    )
    testHandler.mixedInputRawBuffer = testHandler.mixedInputSegmentStream.activeRawBuffer
    testHandler.mixedAlphanumericalBuffer = testHandler.mixedInputSegmentStream.activeRawText
    testHandler.assembler.cursor = 1
    testSession.switchState(testHandler.generateStateOfCandidates(dodge: false))

    guard let nanIndex = testSession.state.candidates.firstIndex(where: { $0.value == "難" }) else {
      Issue.record("候選窗應包含單字『難』以重現 preview 路徑。")
      return
    }

    testSession.candidatePairHighlightChanged(at: nanIndex)

    #expect(testSession.state.displayedText == "themall難生必買")
    #expect(!testSession.state.displayedText.hasSuffix("themall"))
    #expect(testHandler.mixedInputSegmentStream.displayText == "themall南生必買")
  }

  /// Mixed input 的 terminal conversion 應在套用 POM 後同步中文分段文字，
  /// 但 raw segment 必須維持硬邊界，不可被 assembler 的 retokenization flatten 掉。
  @Test
  func test_IH437_MixedInputPOMSyncsChineseSegmentsWithoutFlatteningRawBoundary() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    testHandler.prefs.fetchSuggestionsFromPerceptionOverrideModel = true
    testHandler.prefs.useSCPCTypingMode = false
    testHandler.prefs.useRearCursorMode = false
    clearTestPOM()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 擬 -3
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -4
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); clearTestPOM(); testHandler.clear() }

    typeSentence("su3cl3")
    #expect(testHandler.assembler.assembledSentence.map(\.value).joined() == "你好")
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
    ])

    typeSentence("test")
    #expect(testHandler.mixedInputSegmentStream.displayText == "你好test")
    #expect(testHandler.mixedInputSegmentStream.rawTextSegments == ["test"])

    var suggestion = LMAssembly.OverrideSuggestion()
    suggestion.candidates = [
      (keyArray: ["ㄋㄧˇ"], value: "擬", probability: -0.1, previous: nil),
    ]
    suggestion.overrideCursor = 2
    suggestion.forceHighScoreOverride = true
    testHandler.currentLM.lxPerceptor.testInjectedSuggestion = suggestion

    typeSentence("su3")

    #expect(testHandler.assembler.assembledSentence.map(\.value).joined() == "你好擬")
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      .raw("test"),
      .chinese(text: "擬", readings: ["ㄋㄧˇ"]),
    ])
    #expect(testSession.state.displayedText == "你好test擬")
    #expect(testHandler.committableDisplayText(sansReading: true) == "你好test擬")
  }

  /// Mixed input 問 POM 時應只送 buffer 裡最後一塊 `.chinese` read buffer。
  /// 例如 `你好 + raw(test) + 你` 應送尾段 `你`，不可送 flattened `你好你`。
  @Test
  func test_IH437B_MixedInputPOMQueriesLastChineseReadBufferOnly() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    testHandler.prefs.fetchSuggestionsFromPerceptionOverrideModel = true
    testHandler.prefs.useSCPCTypingMode = false
    testHandler.prefs.useRearCursorMode = false
    clearTestPOM()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 擬 -3
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -4
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); clearTestPOM(); testHandler.clear() }

    let tailGram = Homa.Gram(
      keyArray: ["ㄋㄧˇ"],
      current: "你",
      probability: 0
    )
    let tailQuery = [Homa.GramInPath(gram: tailGram, isExplicit: false)]
    guard let tailPOMKey = tailQuery.generateKeyForPerception(cursor: 1)?.ngramKey else {
      Issue.record("Unable to generate tail-only POM key.")
      return
    }
    #expect(tailPOMKey == "()&()&(ㄋㄧˇ,你)")
    typeSentence("su3cl3test")
    #expect(testHandler.assembler.assembledSentence.map(\.value).joined() == "你好")
    #expect(testHandler.mixedInputSegmentStream.displayText == "你好test")

    testHandler.currentLM.memorizePerception(
      (tailPOMKey, "擬"),
      timestamp: Date().timeIntervalSince1970
    )

    typeSentence("su3")

    #expect(testHandler.assembler.assembledSentence.map(\.value).joined() == "你好擬")
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      .raw("test"),
      .chinese(text: "擬", readings: ["ㄋㄧˇ"]),
    ])
    #expect(testSession.state.displayedText == "你好test擬")
  }

  /// 同一塊中文段內，mixed POM query 必須保留 Homa assembled node segmentation，
  /// 不可把整塊中文段壓成單一 Gram；否則 `未蛇麼` 這類三個單字節點無法被 POM retokenize 成 `為什麼`。
  @Test
  func test_IH437C_MixedInputPOMKeepsAssemblerNodeSegmentationWithinChineseSegment() throws {
    let (testHandler, testSession) = try prepareMixedModeHandler()
    testHandler.prefs.fetchSuggestionsFromPerceptionOverrideModel = true
    testHandler.prefs.useSCPCTypingMode = false
    testHandler.prefs.useRearCursorMode = false
    clearTestPOM()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -4
    ㄨㄟˋ 未 -1
    ㄕㄜˊ 蛇 -1
    ㄇㄜ˙ 麼 -1
    ㄨㄟˋ-ㄕㄜˊ-ㄇㄜ˙ 為什麼 -3
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); clearTestPOM(); testHandler.clear() }

    let query = [
      Homa.GramInPath(gram: .init(keyArray: ["ㄨㄟˋ"], current: "未", probability: 0), isExplicit: false),
      Homa.GramInPath(gram: .init(keyArray: ["ㄕㄜˊ"], current: "蛇", probability: 0), isExplicit: false),
      Homa.GramInPath(gram: .init(keyArray: ["ㄇㄜ˙"], current: "麼", probability: 0), isExplicit: false),
    ]
    guard let pomKey = query.generateKeyForPerception(cursor: 3)?.ngramKey else {
      Issue.record("Unable to generate POM key for 未蛇麼.")
      return
    }
    testHandler.currentLM.memorizePerception(
      (pomKey, "為什麼"),
      timestamp: Date().timeIntervalSince1970
    )

    typeSentence("su3cl3jo4gk6ak7")

    #expect(testHandler.assembler.assembledSentence.map(\.value).joined() == "你好為什麼")
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(
        text: "你好為什麼",
        readings: ["ㄋㄧˇ", "ㄏㄠˇ", "ㄨㄟˋ", "ㄕㄜˊ", "ㄇㄜ˙"]
      ),
    ])
    #expect(testSession.state.displayedText == "你好為什麼")
  }

  /// POM 同步必須以 stream 裡各段 `.chinese.readings` 作為對齊基準；
  /// 只比 reading count 不夠，assembler readings 若與 stream Chinese readings 不一致，
  /// 不可把 Homa 結果寫回 stream，避免 raw boundary 或 cursor drift 被誤蓋。
  @Test
  func test_IH437D_MixedInputPOMSyncRequiresReadingAlignment() throws {
    let (testHandler, _) = try prepareMixedModeHandler()
    testHandler.prefs.fetchSuggestionsFromPerceptionOverrideModel = true
    testHandler.prefs.useSCPCTypingMode = false
    testHandler.prefs.useRearCursorMode = false
    clearTestPOM()
    let testKanjiData = """
    ㄋㄧˇ 你 -1
    ㄋㄧˇ 擬 -3
    ㄏㄠˇ 好 -1
    ㄋㄧˇ-ㄏㄠˇ 你好 -4
    """
    let cleanup = injectTemporaryGrams(testHandler, testKanjiData)
    defer { cleanup(); clearTestPOM(); testHandler.clear() }

    typeSentence("su3cl3testsu3")
    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      .raw("test"),
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
    ])

    _ = try? testHandler.assembler.overrideCandidateLiteral(
      "擬",
      at: testHandler.actualNodeCursorPosition,
      overrideType: .withSpecified,
      enforceRetokenization: true
    )
    #expect(testHandler.assembler.assembledSentence.map(\.value).joined() == "你好擬")

    testHandler.mixedInputSegmentStream = MixedInputSegmentStream(parser: testHandler.composer.parser)
    testHandler.mixedInputSegmentStream.appendChinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])
    testHandler.mixedInputSegmentStream.appendRaw("test")
    testHandler.mixedInputSegmentStream.appendChinese(text: "你", readings: ["ㄏㄞˊ"])

    testHandler.syncMixedInputSegmentStreamChineseSegmentsFromAssembler()

    #expect(testHandler.mixedInputSegmentStream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      .raw("test"),
      .chinese(text: "你", readings: ["ㄏㄞˊ"]),
    ])
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
