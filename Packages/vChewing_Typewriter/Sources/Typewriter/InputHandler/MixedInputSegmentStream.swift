// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation
import Tekkon

// MARK: - MixedInputSegmentStream

/// Ordered source of truth for mixed Chinese/raw typing.
///
/// The stream preserves input history directly:
/// `chinese("你好"), raw("test"), chinese("你好")` renders as
/// `你好test你好` without inferring prefix/suffix/offset after Homa retokenizes.
public struct MixedInputSegmentStream: Sendable {
  public struct ChineseReplacement: Equatable, Sendable {
    public let rawText: String
    public let chineseText: String
    public let readings: [String]

    public init(rawText: String, chineseText: String, readings: [String]) {
      self.rawText = rawText
      self.chineseText = chineseText
      self.readings = readings
    }
  }

  public enum BackspaceDeletion: Equatable, Sendable {
    case rawCharacter(String)
    case chineseReading(text: String, reading: String, globalReadingIndex: Int)
  }

  public enum Segment: Equatable, Sendable {
    case chinese(text: String, readings: [String])
    case raw(String)

    public var displayText: String {
      switch self {
      case let .chinese(text, _): text
      case let .raw(text): text
      }
    }
  }

  public private(set) var segments: [Segment] = []
  public private(set) var activeRawBuffer: MixedInputRawBuffer
  public let parser: Tekkon.MandarinParser

  /// Stream 自管的「游標」，以 stream-unit 為單位（chinese 段每個 reading=1
  /// 單位、raw 段每個 char=1 單位）。Stream 接管時這是視覺游標的唯一真相來源。
  public private(set) var streamCursor: Int = 0
  /// Stream 自管的 marker（用於 marking range）。預設與 streamCursor 同步，
  /// 進入 marking 後才從游標延伸。
  public var streamMarker: Int = 0

  /// Dictionary oracle：dispatcher 注入的字典查詢結果，會 propagate 到
  /// `activeRawBuffer` 與每次 rebuild 後的新 buffer。詳見
  /// `MixedInputRawBuffer.dictionaryWordSplitOracle`。
  public var dictionaryWordSplitOracle: ((_ rawBuffer: String, _ suffixStart: Int) -> Bool)? {
    didSet { activeRawBuffer.dictionaryWordSplitOracle = dictionaryWordSplitOracle }
  }

  public init(parser: Tekkon.MandarinParser = .ofDachen) {
    self.parser = parser
    self.activeRawBuffer = MixedInputRawBuffer(parser: parser)
  }

  public var isEmpty: Bool { segments.isEmpty }

  public var displayText: String {
    segments.map(\.displayText).joined()
  }

  public var displayTextSegments: [String] {
    segments.map(\.displayText).filter { !$0.isEmpty }
  }

  public var activeRawText: String {
    guard case let .raw(text)? = segments.last else { return "" }
    return text
  }

  public var rawTextSegments: [String] {
    segments.compactMap {
      guard case let .raw(text) = $0 else { return nil }
      return text
    }
  }

  public var readingSegments: [[String]] {
    segments.compactMap {
      guard case let .chinese(_, readings) = $0 else { return nil }
      return readings
    }
  }

  public var lastChineseSegment: (text: String, readings: [String], readingStart: Int)? {
    var readingStart = readingCount
    for segment in segments.reversed() {
      switch segment {
      case let .chinese(text, readings):
        readingStart -= readings.count
        return (text, readings, readingStart)
      case .raw:
        continue
      }
    }
    return nil
  }

  public var readingCount: Int {
    readingSegments.reduce(0) { $0 + $1.count }
  }

  /// Stream-unit 總數：chinese 段每個 reading=1 單位、raw 段每個 char=1 單位。
  /// 即 `streamCursor` 的合法上界。
  public var streamUnitCount: Int {
    var total = 0
    for segment in segments {
      switch segment {
      case let .chinese(_, readings): total += readings.count
      case let .raw(text): total += text.count
      }
    }
    return total
  }

  /// 把 stream-unit 為單位的游標換算成 displayText 中的字元位移。
  ///
  /// 與 `displayCursor(forReadingCursor:)` 不同：本 API 把 raw 段裡的每個
  /// char 也算成 1 個游標單位，方便方向鍵在 raw 區裡逐字移動。
  public func displayCursor(forStreamCursor cursor: Int) -> Int {
    var remaining = max(cursor, 0)
    var displayCursor = 0
    for segment in segments {
      switch segment {
      case let .chinese(text, readings):
        let textLength = text.count
        if remaining <= readings.count {
          // readings 與 textUnits 不一定等長：以 min 防呆。
          return displayCursor + min(remaining, textLength)
        }
        displayCursor += textLength
        remaining -= readings.count
      case let .raw(text):
        let length = text.count
        if remaining <= length {
          return displayCursor + remaining
        }
        displayCursor += length
        remaining -= length
      }
    }
    return displayCursor
  }

  public func displayCursor(forReadingCursor readingCursor: Int) -> Int {
    if !activeRawText.isEmpty, readingCursor >= readingCount {
      return displayText.count
    }

    var remainingReadings = max(readingCursor, 0)
    var displayCursor = 0
    for segment in segments {
      switch segment {
      case let .chinese(text, readings):
        let textLength = text.count
        guard remainingReadings > readings.count else {
          return displayCursor + min(remainingReadings, textLength)
        }
        displayCursor += textLength
        remainingReadings -= readings.count
      case let .raw(text):
        guard remainingReadings > 0 else { return displayCursor }
        displayCursor += text.count
      }
    }
    return displayCursor
  }

  public func containsCandidateWithinChineseSegment(keyArray: [String]) -> Bool {
    guard !keyArray.isEmpty else { return false }
    return readingSegments.contains { readings in
      guard keyArray.count <= readings.count else { return false }
      guard !readings.isEmpty else { return false }
      if keyArray.count == readings.count { return readings == keyArray }
      let upperStart = readings.count - keyArray.count
      return (0 ... upperStart).contains { start in
        Array(readings[start ..< start + keyArray.count]) == keyArray
      }
    }
  }

  public var lastRawTextBeforeChineseTail: String {
    for segment in segments.reversed() {
      switch segment {
      case let .raw(text): return text
      case .chinese: continue
      }
    }
    return ""
  }

  public mutating func appendRawKey(_ key: String) -> MixedInputRawBuffer.Commit? {
    if case .raw = segments.last {
      // Continue the tail raw segment.
    } else {
      segments.append(.raw(""))
      activeRawBuffer.clear()
    }
    let transition = activeRawBuffer.receiveWithTransition(key)
    let result: MixedInputRawBuffer.Commit?
    switch transition {
    case let .restartedFromCurrentKey(commit):
      replaceActiveRawText(with: activeRawBuffer.rawBuffer)
      result = commit
    case let .continued(commit):
      replaceActiveRawText(with: activeRawBuffer.rawBuffer)
      result = commit
    case .deadStayedRaw:
      replaceActiveRawText(with: activeRawBuffer.rawBuffer)
      result = nil
    }
    snapCursorToEnd()
    return result
  }

  public mutating func replaceActiveRawWithChinese(
    _ replacement: ChineseReplacement
  ) {
    guard case let .raw(rawText) = segments.last else { return }
    guard rawText.hasSuffix(replacement.rawText) else { return }
    _ = segments.popLast()
    let untouchedRawPrefix = String(rawText.dropLast(replacement.rawText.count))
    appendRaw(untouchedRawPrefix)
    appendChinese(text: replacement.chineseText, readings: replacement.readings)
    activeRawBuffer.clear()
    snapCursorToEnd()
  }

  public func chineseReplacement(
    for commit: MixedInputRawBuffer.Commit,
    chineseText: String,
    readings: [String],
    acceptsLeadingIntonation: Bool
  ) -> ChineseReplacement? {
    let rawText = activeRawText
    guard !rawText.isEmpty else { return nil }
    guard commit.suffix.count <= rawText.count else { return nil }
    guard rawText.hasSuffix(commit.suffix) else { return nil }
    guard acceptsLeadingIntonation || !commit.suffixIsLeadingIntonation else { return nil }
    return .init(
      rawText: commit.suffix,
      chineseText: chineseText,
      readings: readings
    )
  }

  public mutating func appendChinese(text: String, readings: [String]) {
    guard !text.isEmpty else { return }
    if case let .chinese(existingText, existingReadings)? = segments.last {
      segments[segments.count - 1] = .chinese(
        text: existingText + text,
        readings: existingReadings + readings
      )
    } else {
      segments.append(.chinese(text: text, readings: readings))
    }
    snapCursorToEnd()
  }

  public mutating func appendRaw(_ text: String) {
    guard !text.isEmpty else { return }
    if case let .raw(existing)? = segments.last {
      segments[segments.count - 1] = .raw(existing + text)
    } else {
      segments.append(.raw(text))
    }
    snapCursorToEnd()
  }

  @discardableResult
  public mutating func backspace(readingCursor: Int? = nil) -> BackspaceDeletion? {
    let result: BackspaceDeletion?
    if let readingCursor, let deletion = removeChineseReading(before: readingCursor) {
      result = deletion
    } else if let last = segments.last {
      switch last {
      case let .raw(text):
        if let removedCharacter = text.last {
          var newText = text
          newText.removeLast()
          if newText.isEmpty {
            _ = segments.popLast()
          } else {
            segments[segments.count - 1] = .raw(newText)
          }
          rebuildActiveRawBuffer()
          result = .rawCharacter(removedCharacter.description)
        } else {
          result = nil
        }
      case let .chinese(_, readings):
        if !readings.isEmpty {
          result = removeChineseReading(
            inSegmentAt: segments.count - 1,
            readingIndex: max(readings.count - 1, 0)
          )
        } else {
          result = nil
        }
      }
    } else {
      result = nil
    }
    clampCursorAndMarker()
    return result
  }

  public mutating func clear(keepingParser parser: Tekkon.MandarinParser? = nil) {
    segments.removeAll()
    if let parser {
      activeRawBuffer = MixedInputRawBuffer(parser: parser)
    } else {
      activeRawBuffer.clear()
    }
    activeRawBuffer.dictionaryWordSplitOracle = dictionaryWordSplitOracle
    streamCursor = 0
    streamMarker = 0
  }

  public mutating func rebuildActiveRawBuffer() {
    activeRawBuffer = MixedInputRawBuffer(parser: parser)
    activeRawBuffer.dictionaryWordSplitOracle = dictionaryWordSplitOracle
    for key in activeRawText.map(\.description) {
      _ = activeRawBuffer.receive(key)
    }
  }

  public mutating func replaceChineseSegments(withPerReadingValues values: [String]) {
    guard !values.isEmpty else { return }
    var cursor = values.startIndex
    var updatedSegments = [Segment]()
    updatedSegments.reserveCapacity(segments.count)

    for segment in segments {
      switch segment {
      case .raw:
        updatedSegments.append(segment)
      case let .chinese(originalText, readings):
        guard !readings.isEmpty else {
          updatedSegments.append(.chinese(text: originalText, readings: readings))
          continue
        }
        let end = values.index(cursor, offsetBy: readings.count, limitedBy: values.endIndex)
        guard let end else {
          updatedSegments.append(.chinese(text: originalText, readings: readings))
          continue
        }
        let replacement = values[cursor ..< end].joined()
        updatedSegments.append(.chinese(text: replacement, readings: readings))
        cursor = end
      }
    }

    segments = updatedSegments
  }

  public func replacingChineseSegment(
    containing keyArray: [String],
    with candidateText: String,
    readingCursor: Int? = nil
  ) -> Self {
    var copy = self
    _ = copy.replaceChineseSegment(containing: keyArray, with: candidateText, readingCursor: readingCursor)
    return copy
  }

  @discardableResult
  public mutating func replaceChineseSegment(
    containing keyArray: [String],
    with candidateText: String,
    readingCursor: Int? = nil
  ) -> Bool {
    guard !keyArray.isEmpty, candidateText.count == keyArray.count else { return false }
    var readingBase = 0
    for segmentIndex in segments.indices {
      guard case let .chinese(originalText, readings) = segments[segmentIndex] else { continue }
      defer { readingBase += readings.count }
      guard keyArray.count <= readings.count else { continue }
      let textUnits = originalText.map(\.description)
      guard textUnits.count == readings.count else { return false }
      let upperStart = readings.count - keyArray.count
      var candidateStarts = [Int]()
      for start in 0 ... upperStart {
        let end = start + keyArray.count
        guard Array(readings[start ..< end]) == keyArray else { continue }
        candidateStarts.append(start)
      }
      guard !candidateStarts.isEmpty else { continue }
      let selectedStart: Int?
      if let readingCursor {
        selectedStart = candidateStarts.first { start in
          let lower = readingBase + start
          let upper = lower + keyArray.count
          return (lower ... upper).contains(readingCursor)
        }
        guard selectedStart != nil else { continue }
      } else {
        selectedStart = candidateStarts.first
      }
      guard let selectedStart else { continue }
      let selectedEnd = selectedStart + keyArray.count
      var updatedTextUnits = textUnits
      updatedTextUnits.replaceSubrange(selectedStart ..< selectedEnd, with: candidateText.map(\.description))
      segments[segmentIndex] = .chinese(text: updatedTextUnits.joined(), readings: readings)
      return true
    }
    return false
  }

  private mutating func removeChineseReading(before readingCursor: Int) -> BackspaceDeletion? {
    guard readingCursor > 0 else { return nil }
    var readingBase = 0
    for segmentIndex in segments.indices {
      guard case let .chinese(_, readings) = segments[segmentIndex] else { continue }
      let upper = readingBase + readings.count
      defer { readingBase = upper }
      guard readingCursor <= upper else { continue }
      let readingIndex = max(min(readingCursor - readingBase - 1, readings.count - 1), 0)
      return removeChineseReading(
        inSegmentAt: segmentIndex,
        readingIndex: readingIndex,
        globalReadingIndex: readingBase + readingIndex
      )
    }
    return nil
  }

  private mutating func removeChineseReading(
    inSegmentAt segmentIndex: Int,
    readingIndex: Int,
    globalReadingIndex explicitGlobalReadingIndex: Int? = nil
  ) -> BackspaceDeletion? {
    guard segments.indices.contains(segmentIndex) else { return nil }
    guard case let .chinese(text, readings) = segments[segmentIndex] else { return nil }
    guard !text.isEmpty, !readings.isEmpty else { return nil }
    let textUnits = text.map(\.description)
    guard textUnits.count == readings.count else { return nil }
    guard textUnits.indices.contains(readingIndex), readings.indices.contains(readingIndex) else { return nil }

    let removedText = textUnits[readingIndex]
    let removedReading = readings[readingIndex]
    let globalReadingIndex = explicitGlobalReadingIndex ?? readingsGlobalIndex(
      segmentIndex: segmentIndex,
      localReadingIndex: readingIndex
    )

    var updatedTextUnits = textUnits
    updatedTextUnits.remove(at: readingIndex)
    var updatedReadings = readings
    updatedReadings.remove(at: readingIndex)

    if updatedTextUnits.isEmpty {
      segments.remove(at: segmentIndex)
    } else {
      segments[segmentIndex] = .chinese(text: updatedTextUnits.joined(), readings: updatedReadings)
    }
    rebuildActiveRawBuffer()
    return .chineseReading(text: removedText, reading: removedReading, globalReadingIndex: globalReadingIndex)
  }

  private func readingsGlobalIndex(segmentIndex: Int, localReadingIndex: Int) -> Int {
    var base = 0
    for index in segments.indices {
      guard index < segmentIndex else { break }
      guard case let .chinese(_, readings) = segments[index] else { continue }
      base += readings.count
    }
    return base + localReadingIndex
  }

  private mutating func replaceActiveRawText(with text: String) {
    guard case .raw = segments.last else { return }
    if text.isEmpty {
      _ = segments.popLast()
    } else {
      segments[segments.count - 1] = .raw(text)
    }
  }

  // MARK: - Cursor / Marker management

  /// 把游標與 marker 都吸到 stream 的尾端。所有「新輸入」入口都會呼叫之，
  /// 與 assembler 在 mixed 接管時一直把 cursor 推到尾端的舊行為一致。
  public mutating func snapCursorToEnd() {
    streamCursor = streamUnitCount
    streamMarker = streamCursor
  }

  /// 確保 cursor / marker 都在 [0, streamUnitCount] 範圍內。
  public mutating func clampCursorAndMarker() {
    let upper = streamUnitCount
    streamCursor = min(max(streamCursor, 0), upper)
    streamMarker = min(max(streamMarker, 0), upper)
  }

  /// 把指定的 stream-unit 位置換算成「該位置之前累計的 chinese reading 數」，
  /// 用以同步 `assembler.cursor`——assembler 只看 chinese readings，
  /// 候選窗 anchor / 上下候選 / Enter commit 等都據此定位。
  public func chineseReadingPrefixCount(forStreamCursor cursor: Int) -> Int {
    var remaining = max(cursor, 0)
    var count = 0
    for segment in segments {
      switch segment {
      case let .chinese(_, readings):
        let length = readings.count
        if remaining <= length {
          return count + remaining
        }
        count += length
        remaining -= length
      case let .raw(text):
        let length = text.count
        if remaining <= length { return count }
        remaining -= length
      }
    }
    return count
  }

  /// 把 streamCursor 設為指定值（會自動 clamp），並同步重置 streamMarker。
  public mutating func setStreamCursor(_ position: Int) {
    streamCursor = min(max(position, 0), streamUnitCount)
    streamMarker = streamCursor
  }

  /// 步進游標：方向鍵每次按下移動一個 stream-unit。回傳是否真的動了。
  @discardableResult
  public mutating func moveStreamCursorBackward(isMarker: Bool = false) -> Bool {
    if isMarker {
      guard streamMarker > 0 else { return false }
      streamMarker -= 1
      return true
    }
    guard streamCursor > 0 else { return false }
    streamCursor -= 1
    streamMarker = streamCursor
    return true
  }

  @discardableResult
  public mutating func moveStreamCursorForward(isMarker: Bool = false) -> Bool {
    let upper = streamUnitCount
    if isMarker {
      guard streamMarker < upper else { return false }
      streamMarker += 1
      return true
    }
    guard streamCursor < upper else { return false }
    streamCursor += 1
    streamMarker = streamCursor
    return true
  }

  @discardableResult
  public mutating func moveStreamCursorToHome(isMarker: Bool = false) -> Bool {
    if isMarker {
      guard streamMarker != 0 else { return false }
      streamMarker = 0
      return true
    }
    guard streamCursor != 0 else { return false }
    streamCursor = 0
    streamMarker = 0
    return true
  }

  @discardableResult
  public mutating func moveStreamCursorToEnd(isMarker: Bool = false) -> Bool {
    let upper = streamUnitCount
    if isMarker {
      guard streamMarker != upper else { return false }
      streamMarker = upper
      return true
    }
    guard streamCursor != upper else { return false }
    streamCursor = upper
    streamMarker = upper
    return true
  }

  /// 跨 segment 跳：往前 (toFront=true) 找到下一個 segment 邊界、或往後找上一個。
  /// 若已位於該方向的端點則回傳 false。
  @discardableResult
  public mutating func jumpStreamCursorBySegment(
    toFront: Bool, isMarker: Bool = false
  ) -> Bool {
    let boundaries = segmentBoundaries
    let current = isMarker ? streamMarker : streamCursor
    let target: Int? = toFront
      ? boundaries.first { $0 > current }
      : boundaries.reversed().first { $0 < current }
    guard let target else { return false }
    if isMarker {
      streamMarker = target
    } else {
      streamCursor = target
      streamMarker = target
    }
    return true
  }

  /// 所有 segment 邊界（含 0 與 streamUnitCount）。
  private var segmentBoundaries: [Int] {
    var result: [Int] = [0]
    var acc = 0
    for segment in segments {
      switch segment {
      case let .chinese(_, readings): acc += readings.count
      case let .raw(text): acc += text.count
      }
      result.append(acc)
    }
    return result
  }

  /// 將給定的 stream-unit 區間擷取為「每個單位對應的 token」陣列：
  /// chinese 單位回傳對應 reading、raw 單位回傳對應 char 本身。
  /// 主要供 marking range 顯示 / 使用者語彙操作的最佳近似使用。
  public func tokensForStreamRange(_ range: Range<Int>) -> [String] {
    guard !range.isEmpty else { return [] }
    var tokens: [String] = []
    var unitBase = 0
    for segment in segments {
      switch segment {
      case let .chinese(_, readings):
        let segLength = readings.count
        let segRange = unitBase ..< unitBase + segLength
        if let overlap = clampedOverlap(range, segRange) {
          for i in overlap {
            tokens.append(readings[i - unitBase])
          }
        }
        unitBase += segLength
      case let .raw(text):
        let segLength = text.count
        let segRange = unitBase ..< unitBase + segLength
        if let overlap = clampedOverlap(range, segRange) {
          let chars = Array(text)
          for i in overlap {
            tokens.append(String(chars[i - unitBase]))
          }
        }
        unitBase += segLength
      }
    }
    return tokens
  }

  private func clampedOverlap(_ a: Range<Int>, _ b: Range<Int>) -> Range<Int>? {
    let lower = max(a.lowerBound, b.lowerBound)
    let upper = min(a.upperBound, b.upperBound)
    guard lower < upper else { return nil }
    return lower ..< upper
  }
}
