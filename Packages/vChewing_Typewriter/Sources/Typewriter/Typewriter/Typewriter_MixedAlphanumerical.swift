// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation
import Tekkon

// MARK: - MixedAlphanumericalTypewriter

@frozen
public struct MixedAlphanumericalTypewriter<Handler: InputHandlerProtocol>: TypewriterProtocol {
  // MARK: Lifecycle

  public init(_ handler: Handler) {
    self.handler = handler
  }

  // MARK: Public

  public let handler: Handler

  public func handle(_ input: some InputSignalProtocol) -> Bool? {
    guard let session = handler.session else { return nil }
    guard !handler.composer.isPinyinMode else {
      return BPMFFullMatchTypewriter(handler).handle(input)
    }
    // 確保字典 oracle 已就位：當 active raw 起點切到字典詞中間時，
    // RawBuffer 會強制把當前鍵 dead-restart，避免 Trie 把英文字尾巴
    // 與新鍵黏成漢字（例如 `private` + `j6` 不再被吞成 `ej6→ㄍㄨˊ`）。
    if handler.mixedInputSegmentStream.dictionaryWordSplitOracle == nil {
      handler.mixedInputSegmentStream.dictionaryWordSplitOracle = { rawText, suffixStart in
        guard let token = EnglishWordLexicon.tokenSplitByTerminalSuffix(
          rawText: rawText,
          suffixStart: suffixStart
        ) else { return false }
        return EnglishWordLexicon.bundled.containsExactToken(token)
      }
    }
    // 波浪符號鍵（symbol menu physical key）應交還上層分診流程處理。
    // mixed mode 若此時已有可提交內容，先提交全部內容，再放行按鍵事件。
    if input.isSymbolMenuPhysicalKey {
      if !handler.isConsideredEmptyForNow {
        let textToCommit = handler.mixedInputSegmentStream.isEmpty
          ? handler.committableDisplayText(sansReading: true, includeMixedAlphanumericalPrefix: false)
          : handler.mixedInputSegmentStream.displayText
        handler.composer.clear()
        handler.mixedInputRawBuffer.clear()
        handler.mixedInputSegmentStream.clear(keepingParser: handler.composer.parser)
        handler.mixedAlphanumericalBuffer.removeAll()
        session.switchState(State.ofCommitting(textToCommit: textToCommit))
      }
      return nil
    }
    // Space 是大千注音的一聲鍵，mixed mode 不可把它當成 finalize / commit。
    // 讓 Space 與其他 printable key 一樣進入 segment stream / raw-tail validator。
    // In mixed mode, Option+main-area ASCII keys should commit
    // raw ASCII immediately. Shift still decides whether the committed glyph is the
    // base or shifted ASCII variant, but Option glyph substitutions are ignored.
    if let literalASCIIText = resolveLiteralASCIIMainAreaText(input) {
      return commitLiteralASCIIImmediately(literalASCIIText, session: session)
    }
    let isPunctuationChar = !input.text.isEmpty
      && input.text.unicodeScalars.allSatisfy(isPunctCharOrSymbol)
    guard !(input.isReservedKey || input.isNumericPadKey || input.isNonLaptopFunctionKey)
      || isPunctuationChar
      || input.isSpace
    else {
      return nil
    }

    // 大寫英文字母保留原大小寫。
    // Shift+符號與 ASCII 標點在 mixed 上下文中需保留可見字元語義，
    // 避免被 charactersIgnoringModifiers 還原為基底鍵而誤入注音判斷。
    let visibleInputText = resolveVisibleInputText(input)
    let isASCIIPunctuation = visibleInputText.unicodeScalars.count == 1
      && visibleInputText.unicodeScalars.allSatisfy {
        $0.isASCII && isPunctCharOrSymbol($0)
      }
    let isUppercaseLetter = visibleInputText.range(of: "^[A-Z]$", options: .regularExpression) != nil
    let bufferHasASCIIAlnum = handler.mixedAlphanumericalBuffer.range(
      of: "[A-Za-z0-9]",
      options: .regularExpression
    ) != nil
    let baseInputTextIgnoringModifiers = (input.inputTextIgnoringModifiers ?? input.text)
      .lowercased().applyingTransformFW2HW(reverse: false)
    let isBaseInputPhoneticKey = handler.composer.inputValidityCheck(charStr: baseInputTextIgnoringModifiers)
    // 設計選擇（非 Trie 特例）：在 mixed 模式上層 dispatch 必須先把
    // 「同一個鍵在當下情境該走哪條路」分類清楚。ASCII 標點若：
    //   (a) 帶 Shift（Shift+標點通常表達使用者明確要 ASCII 字面值），或
    //   (b) buffer 已含 ASCII 英數而當前鍵又不是合法注音鍵
    //       （保持英文輸入流不被打斷）
    // 則直接走 ASCII 提交。此判斷是鍵分類的本質，不是繞過 Trie——
    // Trie 從未看到過這顆鍵，因此不存在「演算法特例」之說。
    let forceASCIIPunctuationPath = isASCIIPunctuation && (
      input.isShiftHold || (bufferHasASCIIAlnum && !isBaseInputPhoneticKey)
    )

    var inputText: String
    switch (isUppercaseLetter, forceASCIIPunctuationPath) {
    case (_, true), (true, _):
      inputText = visibleInputText
    default:
      inputText = (input.inputTextIgnoringModifiers ?? input.text)
      inputText = inputText.lowercased().applyingTransformFW2HW(reverse: false)
    }
    let isPhoneticKeyRaw = handler.composer.inputValidityCheck(charStr: inputText)

    // 若當前鍵（含修飾鍵）在標點詞庫有可用項，
    // 視為 CJK 標點輸入，優先回到既有標點管線處理。
    // 但若目前鍵位本身就是合法注音鍵，則必須讓注音輸入優先。
    // 設計選擇（非 Trie 特例）：Shift+? 永遠保留 ASCII `?` 字面值，
    // 不被吸成 CJK 全形 `？`。`?` 在 mixed 程式輸入情境太常見，
    // 而 `？` 仍可由其他輸入路徑（候選窗、注音 `2/?`）取得。
    // 其餘 Shift 標點（例如 Shift+` 的 ~）仍維持既有 CJK 標點查詢能力。
    let punctuationQueryStrings = handler.punctuationQueryStrings(input: input)
    let isShiftQuestionMark = input.isShiftHold && ["?", "？"].contains(visibleInputText)

    let matchesCJKPunctuation = !isShiftQuestionMark && isPunctuationChar
      && !isPhoneticKeyRaw && punctuationQueryStrings.contains {
        handler.currentLM.hasUnigramsFor(keyArray: [$0])
      }
    if matchesCJKPunctuation {
      if !handler.mixedInputSegmentStream.isEmpty {
        let textToCommit = handler.mixedInputSegmentStream.displayText
        handler.composer.clear()
        handler.mixedInputRawBuffer.clear()
        handler.mixedInputSegmentStream.clear(keepingParser: handler.composer.parser)
        handler.mixedAlphanumericalBuffer.removeAll()
        session.switchState(State.ofCommitting(textToCommit: textToCommit))
      }
      return nil
    }

    guard !input.isControlHold, !input.isOptionHold, !input.isCommandHold else { return nil }
    // 移除對空 buffer 的 Shift+大寫字母提前返回，改由下方統一處理（保留大寫）。
    let isPhoneticKey = forceASCIIPunctuationPath ? false : isPhoneticKeyRaw
    let isASCIIPrintable = inputText.range(of: "^[ -~]$", options: .regularExpression) != nil
    guard isPhoneticKey || isASCIIPrintable else { return nil }

    var nextStream = handler.mixedInputSegmentStream
    if nextStream.isEmpty {
      nextStream = mixedStreamSeededFromCurrentComposition()
    }
    _ = nextStream.appendRawKey(inputText)
    handler.mixedInputSegmentStream = nextStream

    let rawBufferForTerminalCommit = handler.mixedInputSegmentStream.activeRawBuffer
    let terminalCommit = rawBufferForTerminalCommit.currentTerminalCommit

    if !forceASCIIPunctuationPath,
       applyTerminalSuffixCommit(
         rawBuffer: rawBufferForTerminalCommit,
         terminalCommit: terminalCommit,
         inputInvalid: input.isInvalid,
         session: session
       ) {
      return true
    }

    handler.composer.clear()
    handler.mixedInputRawBuffer = handler.mixedInputSegmentStream.activeRawBuffer
    handler.mixedAlphanumericalBuffer = handler.mixedInputSegmentStream.activeRawText
    session.switchState(handler.generateStateOfInputting())
    return true
  }

  // MARK: Private

  private struct TerminalSuffixCandidate {
    let suffixText: String
    let readingKey: String
    let candidateText: String
  }

  @inline(__always)
  private func isPunctCharOrSymbol(_ scalar: String.UnicodeScalarView.Element) -> Bool {
    CharacterSet.punctuationCharacters.contains(scalar) || CharacterSet.symbols.contains(scalar)
  }

  private func mixedStreamSeededFromCurrentComposition() -> MixedInputSegmentStream {
    var stream = MixedInputSegmentStream(parser: handler.composer.parser)
    let chineseText = handler.committableDisplayText(
      sansReading: true,
      includeMixedAlphanumericalPrefix: false
    )
    guard !chineseText.isEmpty else { return stream }
    stream.appendChinese(
      text: chineseText,
      readings: Array(handler.assembler.actualKeys)
    )
    handler.assembler.clear()
    handler.composer.clear()
    return stream
  }

  private func applyTerminalSuffixCommit(
    rawBuffer: MixedInputRawBuffer,
    terminalCommit: MixedInputRawBuffer.Commit?,
    inputInvalid: Bool,
    session: Session
  ) -> Bool {
    guard let candidate = terminalSuffixCandidate(
      rawBuffer: rawBuffer,
      terminalCommit: terminalCommit
    ) else { return false }

    guard !inputInvalid, (try? handler.assembler.insertKey(candidate.readingKey)) != nil else {
      errorCallback("3CF278C9-C: 得檢查對應的語言模組的 hasUnigramsFor() 是否有誤判之情形。")
      return true
    }

    let textToCommit = ""
    handler.composer.clear()
    var stream = handler.mixedInputSegmentStream
    if stream.isEmpty {
      stream = mixedStreamSeededFromCurrentComposition()
      if !rawBuffer.rawBuffer.isEmpty {
        for key in rawBuffer.rawBuffer.map(\.description) {
          _ = stream.appendRawKey(key)
        }
      }
    }
    if let replacement = stream.chineseReplacement(
      for: .init(suffix: candidate.suffixText, phonabet: candidate.readingKey),
      chineseText: candidate.candidateText,
      readings: candidate.readingKey.components(separatedBy: handler.keySeparator),
      acceptsLeadingIntonation: handler.prefs.acceptLeadingIntonations
    ) {
      stream.replaceActiveRawWithChinese(replacement)
    }
    handler.mixedInputSegmentStream = stream
    if let mixedPOMQuery = handler.mixedInputPOMQueryOverrideForLastChineseSegment() {
      handler.retrievePOMSuggestions(
        apply: true,
        mixedInputReadBufferOverride: mixedPOMQuery
      )
      handler.syncMixedInputSegmentStreamChineseSegmentsFromAssembler()
    }
    handler.mixedInputRawBuffer = handler.mixedInputSegmentStream.activeRawBuffer
    handler.mixedAlphanumericalBuffer = handler.mixedInputSegmentStream.activeRawText

    var inputting = handler.generateStateOfInputting()
    inputting.textToCommit = textToCommit
    session.switchState(inputting)
    handler.handleTypewriterSCPCTasks()
    return true
  }

  private func terminalSuffixCandidate(
    rawBuffer: MixedInputRawBuffer,
    terminalCommit: MixedInputRawBuffer.Commit?
  ) -> TerminalSuffixCandidate? {
    guard let terminalCommit else { return nil }
    let suffixText = terminalCommit.suffix
    guard rawBuffer.rawBuffer.hasSuffix(suffixText) else { return nil }
    if shouldVetoTerminalCommitForCompletedEnglishToken(rawText: rawBuffer.rawBuffer) { return nil }
    guard handler.prefs.acceptLeadingIntonations || !terminalCommit.suffixIsLeadingIntonation else { return nil }
    let candidate = buildTerminalSuffixCandidate(suffixText: suffixText)
    if handler.prefs.filterStandalonePhonabetInMixedAlphanumerical,
       let candidate,
       isStandaloneSinglePhonabetCandidate(candidate) { return nil }
    return candidate
  }

  private func shouldVetoTerminalCommitForCompletedEnglishToken(rawText: String) -> Bool {
    // (1) 已含 trailing word boundary（空格）後的 completed token：原條件保留。
    if let completedToken = EnglishWordLexicon.completedASCIIToken(beforeTrailingBoundary: rawText),
       EnglishWordLexicon.bundled.containsExactToken(completedToken) {
      return true
    }
    return false
  }

  /// 判定 terminal commit 的最佳候選字是否就是 phonabet 自己（例如 reading=`ㄅ` 且
  /// bestCandidate 也是 `ㄅ`）——這代表 LM 對該單聲注音查不到真正漢字、只能 fall back
  /// 回 reading key 自己。由 `filterStandalonePhonabetInMixedAlphanumerical`
  /// preference 控制是否擋掉。能查到真漢字（如 `ㄕ→詩`、`ㄓ→之`）的單聲注音不在此列。
  private func isStandaloneSinglePhonabetCandidate(_ candidate: TerminalSuffixCandidate) -> Bool {
    let readings = candidate.readingKey.components(separatedBy: handler.keySeparator)
    guard readings.count == 1, let reading = readings.first else { return false }
    guard reading.unicodeScalars.count == 1 else { return false }
    return candidate.candidateText == reading
  }

  private func buildTerminalSuffixCandidate(suffixText: String) -> TerminalSuffixCandidate? {
    if !handler.prefs.acceptLeadingIntonations,
       suffixText.first.map({ String($0) }).map({ firstChar in
         var firstKeyTest = handler.composer
         firstKeyTest.clear()
         firstKeyTest.receiveKey(fromString: firstChar)
         return firstKeyTest.hasIntonation(withNothingElse: true)
       }) == true {
      return nil
    }

    var trialComposer = handler.composer
    trialComposer.clear()
    trialComposer.receiveSequence(suffixText, isRomaji: false)

    // 若「允許聲調前置鍵入」已關閉，後綴不能以獨立聲調鍵作為首鍵。
    if !handler.prefs.acceptLeadingIntonations, let firstChar = suffixText.first?.description {
      var firstKeyTest = handler.composer
      firstKeyTest.clear()
      firstKeyTest.receiveKey(fromString: firstChar)
      if firstKeyTest.hasIntonation(withNothingElse: true) { return nil }
    }

    guard trialComposer.isPronounceable, trialComposer.hasIntonation() else {
      return nil
    }

    guard let readingKey = trialComposer.phonabetKeyForQuery(
      pronounceableOnly: handler.prefs.acceptLeadingIntonations
    ) else {
      return nil
    }

    guard !readingKey.contains(handler.keySeparator),
          readingKey.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    else {
      return nil
    }

    guard handler.currentLM.hasUnigramsForFast(keyArray: [readingKey]) else {
      return nil
    }

    return .init(
      suffixText: suffixText,
      readingKey: readingKey,
      candidateText: bestCandidateText(for: readingKey)
    )
  }

  private func bestCandidateText(for readingKey: String) -> String {
    let keyArray = readingKey.components(separatedBy: handler.keySeparator)
    if let best = handler.currentLM.lookupHub.grams(for: keyArray)
      .max(by: { $0.probability < $1.probability }) {
      return best.value
    }
    return readingKey
  }

  private func resolveVisibleInputText(_ input: some InputSignalProtocol) -> String {
    let transformedInputText = input.text.applyingTransformFW2HW(reverse: false)
    guard input.isShiftHold else { return transformedInputText }

    let transformedInputTextIgnoringModifiers = (input.inputTextIgnoringModifiers ?? input.text)
      .applyingTransformFW2HW(reverse: false)

    // 僅在事件未提供 shifted glyph 時，才以 keyCode 查表回填可見字元。
    guard transformedInputText == transformedInputTextIgnoringModifiers else {
      return transformedInputText
    }

    let keyboardLayout = inferredLatinKeyboardLayout()
    guard let mappedTuple = keyboardLayout.mapTable[input.keyCode] else {
      return transformedInputText
    }
    return mappedTuple.1.applyingTransformFW2HW(reverse: false)
  }

  private func resolveLiteralASCIIMainAreaText(_ input: some InputSignalProtocol) -> String? {
    guard input.isOptionHold,
          !input.isControlHold,
          !input.isCommandHold,
          !input.isSymbolMenuPhysicalKey
    else {
      return nil
    }

    guard let mappedTuple = inferredLatinKeyboardLayout().mapTable[input.keyCode] else {
      return nil
    }

    let literalASCII = (input.isShiftHold ? mappedTuple.1 : mappedTuple.0)
      .applyingTransformFW2HW(reverse: false)
    guard literalASCII.range(of: "^[ -~]$", options: .regularExpression) != nil else {
      return nil
    }
    return literalASCII
  }

  private func commitLiteralASCIIImmediately(_ text: String, session: Session) -> Bool {
    guard !text.isEmpty else { return false }

    let pendingText = handler.committableDisplayText(sansReading: true, includeMixedAlphanumericalPrefix: false)
      + handler.mixedAlphanumericalBuffer
    handler.composer.clear()
    handler.mixedInputRawBuffer.clear()
    handler.mixedAlphanumericalBuffer.removeAll()

    if !pendingText.isEmpty {
      session.switchState(State.ofCommitting(textToCommit: pendingText))
    }
    session.switchState(State.ofCommitting(textToCommit: text))
    return true
  }

  private func inferredLatinKeyboardLayout() -> LatinKeyboardMappings {
    // 非拼音路徑統一視為 QWERTY，避免額外讀取 keyboardParser（UserDefaults）。
    if !handler.composer.isPinyinMode { return .qwerty }
    return LatinKeyboardMappings(rawValue: handler.prefs.basicKeyboardLayout) ?? .qwerty
  }
}
