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
    let previousActiveRawText = activeRawText
    let transition = activeRawBuffer.receiveWithTransition(key)
    switch transition {
    case let .restartedFromCurrentKey(commit):
      guard shouldStartNewRawSegmentAfterRestart(previousRawText: previousActiveRawText, currentKey: key) else {
        replaceActiveRawText(with: activeRawBuffer.rawBuffer)
        return commit
      }
      replaceActiveRawText(with: previousActiveRawText)
      segments.append(.raw(key))
      activeRawBuffer = MixedInputRawBuffer(parser: parser)
      let freshTransition = activeRawBuffer.receiveWithTransition(key)
      return freshTransition.commit ?? commit
    case let .continued(commit):
      replaceActiveRawText(with: activeRawBuffer.rawBuffer)
      return commit
    case .deadStayedRaw:
      replaceActiveRawText(with: activeRawBuffer.rawBuffer)
      return nil
    }
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
  }

  public mutating func appendRaw(_ text: String) {
    guard !text.isEmpty else { return }
    if case let .raw(existing)? = segments.last {
      segments[segments.count - 1] = .raw(existing + text)
    } else {
      segments.append(.raw(text))
    }
  }

  @discardableResult
  public mutating func backspace(readingCursor: Int? = nil) -> BackspaceDeletion? {
    if let readingCursor, let deletion = removeChineseReading(before: readingCursor) {
      return deletion
    }

    guard let last = segments.last else { return nil }
    switch last {
    case let .raw(text):
      guard let removedCharacter = text.last else { return nil }
      var newText = text
      newText.removeLast()
      if newText.isEmpty {
        _ = segments.popLast()
      } else {
        segments[segments.count - 1] = .raw(newText)
      }
      rebuildActiveRawBuffer()
      return .rawCharacter(removedCharacter.description)
    case let .chinese(_, readings):
      guard !readings.isEmpty else { return nil }
      return removeChineseReading(inSegmentAt: segments.count - 1, readingIndex: max(readings.count - 1, 0))
    }
  }

  public mutating func clear(keepingParser parser: Tekkon.MandarinParser? = nil) {
    segments.removeAll()
    if let parser {
      activeRawBuffer = MixedInputRawBuffer(parser: parser)
    } else {
      activeRawBuffer.clear()
    }
  }

  public mutating func rebuildActiveRawBuffer() {
    activeRawBuffer = MixedInputRawBuffer(parser: parser)
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

  private func shouldStartNewRawSegmentAfterRestart(previousRawText: String, currentKey: String) -> Bool {
    guard previousRawText.count == 1,
          let previous = previousRawText.unicodeScalars.first,
          previous.isASCII && CharacterSet.letters.contains(previous),
          previousRawText == previousRawText.uppercased(),
          let current = currentKey.unicodeScalars.first,
          current.isASCII && CharacterSet.decimalDigits.contains(current)
    else { return false }
    return true
  }

  private mutating func replaceActiveRawText(with text: String) {
    guard case .raw = segments.last else { return }
    if text.isEmpty {
      _ = segments.popLast()
    } else {
      segments[segments.count - 1] = .raw(text)
    }
  }
}
