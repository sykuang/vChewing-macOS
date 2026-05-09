// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation
import Homa
import Testing

@testable import MainAssembly4Darwin

extension MainAssemblyTests {
  /// 測試 CapsLock 中英切換場景下 performServerActivation 的快速路徑。
  ///
  /// 當副本已處於活動狀態、為當前副本、且 inputHandler 存在時，
  /// 重複呼叫 performServerActivation 不應重新建構 inputHandler。
  @Test
  func test501_ActivationFastPath_SkipsInitInputHandler() throws {
    // 確保 testSession 已初始化且處於活動狀態。
    #expect(testSession.isActivated)
    #expect(testSession.inputHandler != nil)

    // 將 testSession 設為 current（模擬正常啟用狀態）。
    InputSession.current = testSession

    // 記錄當前 inputHandler 的身份（使用 ObjectIdentifier）。
    let handlerBefore = testSession.inputHandler
    let identityBefore = ObjectIdentifier(handlerBefore!)

    // 模擬 CapsLock 切換回來：呼叫 performServerActivation。
    // 由於 isActivated == true、Self.current?.id == id、inputHandler != nil，
    // 應命中快速路徑，不會呼叫 initInputHandler()。
    testSession.performServerActivation(client: testClient)

    // 驗證 inputHandler 未被重新建構。
    let handlerAfter = testSession.inputHandler
    let identityAfter = ObjectIdentifier(handlerAfter!)
    #expect(
      identityBefore == identityAfter,
      "快速路徑不應重新建構 inputHandler，但 inputHandler 身份已變更。"
    )

    // 驗證副本仍處於活動狀態。
    #expect(testSession.isActivated)
    #expect(testSession.state.type == .ofEmpty)
  }

  /// 測試 performServerDeactivation 對當前副本為 no-op。
  ///
  /// 當 Self.current?.id == self.id 時，performServerDeactivation 應提前返回，
  /// 不改變 isActivated 狀態，也不重設 inputHandler。
  @Test
  func test502_DeactivationIsNoOpForCurrentSession() throws {
    #expect(testSession.isActivated)
    #expect(testSession.inputHandler != nil)

    InputSession.current = testSession

    let handlerBefore = testSession.inputHandler

    // 呼叫 deactivation；因 Self.current?.id == id，應為 no-op。
    testSession.performServerDeactivation()

    // 驗證 isActivated 未被改變（仍為 true）。
    #expect(
      testSession.isActivated,
      "performServerDeactivation 對當前副本應為 no-op，isActivated 不應被改變。"
    )

    // 驗證 inputHandler 仍然存在。
    #expect(testSession.inputHandler != nil)
    let handlerAfter = testSession.inputHandler
    #expect(
      ObjectIdentifier(handlerBefore!) == ObjectIdentifier(handlerAfter!),
      "performServerDeactivation 對當前副本不應影響 inputHandler。"
    )
  }

  /// 測試快速路徑下的反覆啟用不會累積額外開銷。
  ///
  /// 模擬使用者快速按壓 CapsLock 多次切換中英的場景：
  /// 連續呼叫 performServerActivation 多次，驗證每次都命中快速路徑。
  @Test
  func test503_RapidReactivation_MaintainsHandlerIdentity() throws {
    #expect(testSession.isActivated)
    InputSession.current = testSession

    let identityBefore = ObjectIdentifier(testSession.inputHandler!)

    // 模擬 20 次快速切換（每次 deactivate + activate）。
    for _ in 0 ..< 20 {
      testSession.performServerDeactivation() // no-op（current session）
      testSession.performServerActivation(client: testClient) // 快速路徑
    }

    let identityAfter = ObjectIdentifier(testSession.inputHandler!)
    #expect(
      identityBefore == identityAfter,
      "經過 20 次快速切換後，inputHandler 不應被重新建構。"
    )
    #expect(testSession.isActivated)
    #expect(testSession.state.type == .ofEmpty)
  }

  /// 回歸：CapsLock 切換中英文時會走 resetInputHandler。
  /// reset 時提交內容必須包含尚未遞交的 mixed ASCII buffer。
  @Test
  func test504_CapsLockResetCommitsPendingMixedASCIIBuffer() throws {
    testSession.resetInputHandler(forceComposerCleanup: true)
    testClient.clear()
    testHandler.prefs.mixedAlphanumericalEnabled = true

    typeSentenceOrCandidates("abc")

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "abc")
    #expect(testClient.toString().isEmpty)

    // 模擬 CapsLock 切換路徑中的 resetInputHandler() 行為。
    testSession.resetInputHandler()

    #expect(testClient.toString() == "abc")
    #expect(testSession.state.type == .ofEmpty)
  }

  /// 回歸：mixed segment stream 已經包含中文 + raw tail 全文時，resetInputHandler
  /// 不得再把相容欄位 mixedAlphanumericalBuffer 追加一次。
  @Test
  func test505_ResetCommitsMixedSegmentStreamWithoutDuplicatingRawTail() throws {
    testSession.resetInputHandler(forceComposerCleanup: true)
    testClient.clear()
    testHandler.clear()
    testHandler.prefs.mixedAlphanumericalEnabled = true
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄋㄧˇ"], value: "你", score: -1),
      isFiltering: false
    )
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄏㄠˇ"], value: "好", score: -1),
      isFiltering: false
    )
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄋㄧˇ", "ㄏㄠˇ"], value: "你好", score: -2),
      isFiltering: false
    )
    defer {
      testHandler.currentLM.clearTemporaryData(isFiltering: false)
      testHandler.clear()
      testClient.clear()
    }

    typeSentenceOrCandidates("su3cl3testsu3")

    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你好test你")
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)
    #expect(testHandler.mixedInputSegmentStream.displayText == "你好test你")

    testSession.resetInputHandler()

    #expect(testClient.toString() == "你好test你")
    #expect(testSession.state.type == .ofEmpty)
  }

  /// 回歸：MainAssembly / InputSession 路徑下，mixed stream 中間有 raw segment 時，
  /// 尾端中文選字不可跨 raw boundary，也不可在確認候選後把 raw segment 重複復活。
  @Test
  func test506_MixedStackBufferSelectsTrailingChineseAfterMiddleRaw() throws {
    testSession.resetInputHandler(forceComposerCleanup: true)
    testClient.clear()
    testHandler.clear()
    testHandler.prefs.useSCPCTypingMode = false
    testHandler.prefs.useRearCursorMode = false
    testHandler.prefs.fetchSuggestionsFromPerceptionOverrideModel = false
    testHandler.prefs.mixedAlphanumericalEnabled = true
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄋㄧˇ"], value: "你", score: -1),
      isFiltering: false
    )
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄏㄠˇ"], value: "好", score: -1),
      isFiltering: false
    )
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄏㄠˇ"], value: "郝", score: -2),
      isFiltering: false
    )
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄋㄧˇ", "ㄏㄠˇ"], value: "你好", score: -2),
      isFiltering: false
    )
    defer {
      testHandler.currentLM.clearTemporaryData(isFiltering: false)
      testHandler.clear()
      testClient.clear()
    }

    typeSentenceOrCandidates("su3cl3testcl3")

    #expect(testClient.toString().isEmpty)
    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == "你好test好")
    #expect(testSession.state.cursor == "你好test好".count)
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == ["你好", "test", "好"])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    press(nextCandidateEvent)

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

    testClient.clear()
    press(dataEnterReturn)
    #expect(testClient.toString() == "你好test郝")
    #expect(testSession.state.type == .ofEmpty)
  }

  /// 回歸：mixed mode 在空組字區先輸入 Space 時，Space 應作為 raw segment 保留；
  /// 接著開始輸入注音時，後續中文 segment 不可吞掉、重排或重複前導空白。
  @Test
  func test507_MixedLeadingSpaceThenZhuyinKeepsRawBoundary() throws {
    testSession.resetInputHandler(forceComposerCleanup: true)
    testClient.clear()
    testHandler.clear()
    testHandler.prefs.useSCPCTypingMode = false
    testHandler.prefs.useRearCursorMode = false
    testHandler.prefs.fetchSuggestionsFromPerceptionOverrideModel = false
    testHandler.prefs.mixedAlphanumericalEnabled = true
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄋㄧˇ"], value: "你", score: -1),
      isFiltering: false
    )
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄏㄠˇ"], value: "好", score: -1),
      isFiltering: false
    )
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄏㄠˇ"], value: "郝", score: -2),
      isFiltering: false
    )
    testHandler.currentLM.insertTemporaryData(
      unigram: Homa.Gram(keyArray: ["ㄋㄧˇ", "ㄏㄠˇ"], value: "你好", score: -2),
      isFiltering: false
    )
    defer {
      testHandler.currentLM.clearTemporaryData(isFiltering: false)
      testHandler.clear()
      testClient.clear()
    }

    typeSentenceOrCandidates(" su3cl3")

    #expect(testClient.toString().isEmpty)
    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == " 你好")
    #expect(testSession.state.cursor == " 你好".count)
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == [" ", "你好"])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    press(nextCandidateEvent)

    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == " 你好")
    #expect(testSession.state.cursor == " 你好".count)

    guard let targetIndex = testSession.state.candidates.firstIndex(where: { $0.value == "郝" }) else {
      Issue.record("Expected candidate 郝 for trailing 好 among: \(testSession.state.candidates.map(\.value))")
      return
    }

    testSession.candidatePairHighlightChanged(at: targetIndex)
    #expect(testSession.state.type == .ofCandidates)
    #expect(testSession.state.displayedText == " 你郝")
    #expect(testSession.state.displayTextSegments == [" ", "你郝"])
    #expect(testSession.state.cursor == " 你郝".count)
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == [" ", "你好"])

    testSession.candidatePairSelectionConfirmed(at: targetIndex)
    #expect(testSession.state.type == .ofInputting)
    #expect(testSession.state.displayedText == " 你郝")
    #expect(testSession.state.cursor == " 你郝".count)
    #expect(testHandler.mixedInputSegmentStream.displayTextSegments == [" ", "你郝"])
    #expect(testHandler.mixedInputSegmentStream.activeRawText.isEmpty)
    #expect(testHandler.mixedAlphanumericalBuffer.isEmpty)

    testClient.clear()
    press(dataEnterReturn)
    #expect(testClient.toString() == " 你郝")
    #expect(testSession.state.type == .ofEmpty)
  }
  /// 回歸：合併入口只在系統輸入來源列表顯示 CHT；簡繁由 PrimaryOutputScript
  /// picker 透過 IMK `selectMode(_:)` 切換 hidden sub-mode。
  @Test
  func test507_PrimaryOutputScriptPickerSelectsHiddenIMKSubMode() throws {
    testSession.resetInputHandler(forceComposerCleanup: true)
    testClient.clear()
    defer {
      PrefMgr.shared.primaryOutputScript = 0
      testSession.inputMode = .imeModeCHT
      PrefMgr.shared.mostRecentInputMode = Shared.InputMode.imeModeCHT.rawValue
      testClient.selectedModeIdentifier = nil
    }

    testSession.inputMode = .imeModeCHT
    PrefMgr.shared.primaryOutputScript = 1
    testClient.selectedModeIdentifier = nil

    testSession.applyPrimaryOutputScript()

    #expect(testClient.selectedModeIdentifier == Shared.InputMode.imeModeCHS.rawValue)
    #expect(PrefMgr.shared.mostRecentInputMode == Shared.InputMode.imeModeCHS.rawValue)

    testSession.inputMode = .imeModeCHS
    PrefMgr.shared.primaryOutputScript = 0
    testClient.selectedModeIdentifier = nil

    testSession.applyPrimaryOutputScript()

    #expect(testClient.selectedModeIdentifier == Shared.InputMode.imeModeCHT.rawValue)
    #expect(PrefMgr.shared.mostRecentInputMode == Shared.InputMode.imeModeCHT.rawValue)
  }

  /// 回歸：合併入口在 Info.plist 層只 expose 單一 CHT 系統入口；CHS 保留為 hidden IMK sub-mode。
  @Test
  func test508_InfoPlistShowsSingleVisibleInputSource() throws {
    let projectRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let plistURL = projectRoot
      .appendingPathComponent("Sources")
      .appendingPathComponent("vChewingIME_macOS")
      .appendingPathComponent("Resources")
      .appendingPathComponent("Info.plist")
    let data = try Data(contentsOf: plistURL)
    let plist = try #require(
      PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    )
    let inputMethodServerController = try #require(
      plist["ComponentInputModeDict"] as? [String: Any]
    )
    let visibleInputModes = try #require(
      inputMethodServerController["tsVisibleInputModeOrderedArrayKey"] as? [String]
    )
    #expect(visibleInputModes == [Shared.InputMode.imeModeCHT.rawValue])

    let inputModes = try #require(
      inputMethodServerController["tsInputModeListKey"] as? [String: [String: Any]]
    )
    let cht = try #require(inputModes[Shared.InputMode.imeModeCHT.rawValue])
    let chs = try #require(inputModes[Shared.InputMode.imeModeCHS.rawValue])
    #expect(cht["tsInputModeIsVisibleKey"] as? Bool == true)
    #expect(chs["tsInputModeIsVisibleKey"] as? Bool == false)
  }

}
