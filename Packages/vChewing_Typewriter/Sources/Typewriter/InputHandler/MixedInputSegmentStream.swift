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
    public let prefixRaw: String
    public let chineseText: String
    public let readings: [String]

    public init(rawText: String, prefixRaw: String, chineseText: String, readings: [String]) {
      self.rawText = rawText
      self.prefixRaw = prefixRaw
      self.chineseText = chineseText
      self.readings = readings
    }
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
    let commit = activeRawBuffer.receive(key)
    replaceActiveRawText(with: activeRawBuffer.rawBuffer)
    return commit
  }

  public mutating func replaceActiveRawWithChinese(
    _ replacement: ChineseReplacement
  ) {
    guard case .raw = segments.last else { return }
    _ = segments.popLast()
    appendRaw(replacement.prefixRaw)
    appendChinese(text: replacement.chineseText, readings: replacement.readings)
    activeRawBuffer.clear()
  }

  public func chineseReplacement(
    for commit: MixedInputRawBuffer.Commit,
    chineseText: String,
    readings: [String],
    acceptsLeadingIntonation: Bool,
    requiresWordLikeRawPrefix: Bool
  ) -> ChineseReplacement? {
    let rawText = activeRawText
    guard rawText.count > 1 else { return nil }
    guard commit.suffix.count <= rawText.count else { return nil }
    guard commit.literalPrefix.count == rawText.count - commit.suffix.count else { return nil }
    guard acceptsLeadingIntonation || !commit.literalPrefix.isEmpty else { return nil }
    guard commit.literalPrefix.isEmpty || !requiresWordLikeRawPrefix || Self.isWordLikeRawPrefix(commit.literalPrefix) else {
      return nil
    }
    return .init(
      rawText: rawText,
      prefixRaw: commit.literalPrefix,
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
  public mutating func backspace() -> Bool {
    guard let last = segments.last else { return false }
    switch last {
    case let .raw(text):
      guard !text.isEmpty else { return false }
      var newText = text
      newText.removeLast()
      if newText.isEmpty {
        _ = segments.popLast()
      } else {
        segments[segments.count - 1] = .raw(newText)
      }
      rebuildActiveRawBuffer()
      return true
    case let .chinese(text, readings):
      guard !text.isEmpty else { return false }
      var newText = text
      newText.removeLast()
      var newReadings = readings
      if !newReadings.isEmpty { newReadings.removeLast() }
      if newText.isEmpty {
        _ = segments.popLast()
      } else {
        segments[segments.count - 1] = .chinese(text: newText, readings: newReadings)
      }
      activeRawBuffer.clear()
      return true
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

  private mutating func replaceActiveRawText(with text: String) {
    guard case .raw = segments.last else { return }
    if text.isEmpty {
      _ = segments.popLast()
    } else {
      segments[segments.count - 1] = .raw(text)
    }
  }

  private static func isWordLikeRawPrefix(_ text: String) -> Bool {
    text.range(of: "^[A-Za-z]{3,}[A-Za-z0-9]*$", options: .regularExpression) != nil
  }
}
