// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation
import Tekkon

// MARK: - MixedInputRawBuffer

/// Incremental raw-buffer validator around ZhuyinKeyTrie.
///
/// This type intentionally does not own the IME commit FSM: it records raw keys
/// and per-key trie frames only. Each `receive(_:)` advances the trie once and
/// stores the resulting frame. `backspace()` pops exactly one frame, restoring
/// the parent traversal state without re-scanning the whole raw string.
public struct MixedInputRawBuffer: Sendable {

  public struct ActivePrefix: Equatable, Sendable {
    public let suffix: String
    public let phonabet: String
    public let state: ZhuyinKeyTrie.AdvanceResult

    public init(suffix: String, phonabet: String, state: ZhuyinKeyTrie.AdvanceResult) {
      self.suffix = suffix
      self.phonabet = phonabet
      self.state = state
    }
  }

  public struct Commit: Equatable, Sendable {
    public let suffix: String
    public let phonabet: String

    public init(
      suffix: String,
      phonabet: String
    ) {
      self.suffix = suffix
      self.phonabet = phonabet
    }

    public var suffixIsLeadingIntonation: Bool {
      guard let first = suffix.first else { return false }
      switch first {
      case "3", "4", "6", "7", " ": return true
      default: return false
      }
    }
  }

  public enum Transition: Equatable, Sendable {
    case continued(commit: Commit?)
    case deadStayedRaw
    case restartedFromCurrentKey(commit: Commit?)

    public var commit: Commit? {
      switch self {
      case let .continued(commit), let .restartedFromCurrentKey(commit): commit
      case .deadStayedRaw: nil
      }
    }
  }

  private struct Frame: Sendable {
    let rawKey: Character
    let normalizedKey: String
    let activeCursor: ZhuyinKeyTrie.Cursor?
    let activeSuffixStart: Int?
    let activePhonabet: String
    let state: ZhuyinKeyTrie.AdvanceResult
    let terminalCommit: Commit?
  }

  public private(set) var rawBuffer = ""
  public var displayText: String { rawBuffer }

  public var activeTriePrefix: ActivePrefix? {
    guard let frame = frames.last,
          frame.state != .dead,
          let activeSuffixStart = frame.activeSuffixStart,
          !frame.activePhonabet.isEmpty
    else { return nil }
    let chars = Array(rawBuffer)
    guard chars.indices.contains(activeSuffixStart) else { return nil }
    return .init(
      suffix: String(chars[activeSuffixStart...]),
      phonabet: frame.activePhonabet,
      state: frame.state
    )
  }

  public var currentTerminalCommit: Commit? {
    frames.last?.terminalCommit
  }

  private let parser: Tekkon.MandarinParser
  private var frames: [Frame] = []

  /// Dictionary oracle 注入點：每次 advance 出新 frame 後，
  /// 若 oracle 對「(rawBuffer, activeSuffixStart)」回 true，
  /// 表示 active suffix 起點切開了已成形英文字 → 強制走
  /// dead-restart-from-current-key 路徑，把當前鍵之前的 raw 留給英文。
  ///
  /// 條件：oracle 不是 RawBuffer 自己的職責——它只持有判斷結果。
  /// 預設 nil 時為純 Trie 行為，與舊版完全相容。
  /// 注：closure 故意不標 `@Sendable`，因 caller 通常需要 access
  /// `EnglishWordLexicon.bundled` 等 main-actor isolated 資源。
  public var dictionaryWordSplitOracle: ((_ rawBuffer: String, _ suffixStart: Int) -> Bool)?

  public init(parser: Tekkon.MandarinParser) {
    self.parser = parser
  }

  @discardableResult
  public mutating func receive(_ key: String) -> Commit? {
    receiveWithTransition(key).commit
  }

  @discardableResult
  public mutating func receiveWithTransition(_ key: String) -> Transition {
    guard let rawKey = key.first, key.count == 1 else { return .deadStayedRaw }
    rawBuffer.append(rawKey)

    let trie = ZhuyinKeyTrie.shared(for: parser)
    let normalizedKey = key.lowercased()
    let previous = frames.last
    let previousCursor = previous?.activeCursor ?? trie.rootCursor
    let previousStart = previous?.activeCursor == nil ? rawBuffer.count - 1 : previous?.activeSuffixStart
    let advanced = trie.advance(from: previousCursor, with: normalizedKey)
    var didRestartFromCurrentKey = previous?.activeCursor == nil && previous != nil

    var activeCursor: ZhuyinKeyTrie.Cursor?
    var activeSuffixStart: Int?
    var state: ZhuyinKeyTrie.AdvanceResult
    var activePhonabet: String

    if let cursor = advanced.cursor {
      activeCursor = cursor
      activeSuffixStart = previousStart
      state = advanced.state
      let suffixKeys = normalizedKeys(from: activeSuffixStart)
      activePhonabet = Self.phonabetPreview(for: suffixKeys, parser: parser) ?? ""
    } else {
      let restarted = trie.advance(from: trie.rootCursor, with: normalizedKey)
      if let restartedCursor = restarted.cursor {
        didRestartFromCurrentKey = true
        activeCursor = restartedCursor
        activeSuffixStart = rawBuffer.count - 1
        state = restarted.state
        activePhonabet = Self.phonabetPreview(for: [normalizedKey], parser: parser) ?? ""
      } else {
        activeCursor = nil
        activeSuffixStart = nil
        state = .dead
        activePhonabet = ""
      }
    }

    // Dictionary-oracle gate：若 active suffix 起點切開英文字，視同 Trie dead，
    // 自當前鍵 root-restart。等同把該英文字「seal 給 raw 英文」、新鍵自己跑。
    if let oracle = dictionaryWordSplitOracle,
       let suffixStart = activeSuffixStart,
       suffixStart < rawBuffer.count - 1, // 切開英文字的條件就是 suffix 不只有當前鍵
       oracle(rawBuffer, suffixStart) {
      let restarted = trie.advance(from: trie.rootCursor, with: normalizedKey)
      if let restartedCursor = restarted.cursor {
        didRestartFromCurrentKey = true
        activeCursor = restartedCursor
        activeSuffixStart = rawBuffer.count - 1
        state = restarted.state
        activePhonabet = Self.phonabetPreview(for: [normalizedKey], parser: parser) ?? ""
      } else {
        activeCursor = nil
        activeSuffixStart = nil
        state = .dead
        activePhonabet = ""
        didRestartFromCurrentKey = false
      }
    }

    var frame = Frame(
      rawKey: rawKey,
      normalizedKey: normalizedKey,
      activeCursor: activeCursor,
      activeSuffixStart: activeSuffixStart,
      activePhonabet: activePhonabet,
      state: state,
      terminalCommit: nil
    )
    let terminalCommit = terminalCommit(for: frame)
    frame = Frame(
      rawKey: frame.rawKey,
      normalizedKey: frame.normalizedKey,
      activeCursor: frame.activeCursor,
      activeSuffixStart: frame.activeSuffixStart,
      activePhonabet: frame.activePhonabet,
      state: frame.state,
      terminalCommit: terminalCommit
    )
    frames.append(frame)
    if activeCursor == nil { return .deadStayedRaw }
    if didRestartFromCurrentKey { return .restartedFromCurrentKey(commit: frame.terminalCommit) }
    return .continued(commit: frame.terminalCommit)
  }

  public mutating func backspace() -> Bool {
    guard !rawBuffer.isEmpty else { return false }
    rawBuffer.removeLast()
    _ = frames.popLast()
    return true
  }

  public mutating func clear() {
    rawBuffer.removeAll()
    frames.removeAll()
  }

  private func normalizedKeys(from start: Int?) -> [String] {
    guard let start else { return [] }
    return frames.dropFirst(start).map(\.normalizedKey) + [String(rawBuffer.last!).lowercased()]
  }

  private func terminalCommit(for frame: Frame) -> Commit? {
    guard frame.state == .terminal,
          let activeSuffixStart = frame.activeSuffixStart,
          !frame.activePhonabet.isEmpty
    else { return nil }
    let chars = Array(rawBuffer)
    guard chars.indices.contains(activeSuffixStart) else { return nil }
    let suffix = String(chars[activeSuffixStart...])
    let phonabet = frame.activePhonabet
    return .init(
      suffix: suffix,
      phonabet: phonabet
    )
  }

  private static func phonabetPreview(
    for keys: [String],
    parser: Tekkon.MandarinParser
  ) -> String? {
    directPhonabetPreview(for: keys, parser: parser)
  }

  private static func directPhonabetPreview(
    for keys: [String],
    parser: Tekkon.MandarinParser
  ) -> String? {
    let translatedScalars: [Unicode.Scalar]
    switch parser {
    case .ofDachen:
      translatedScalars = keys.compactMap { key in
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else { return nil }
        return dachenPhonabetMap[scalar]
      }
    default:
      return nil
    }
    guard translatedScalars.count == keys.count else { return nil }
    let preview = String(String.UnicodeScalarView(translatedScalars))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return preview.isEmpty ? nil : preview
  }

  private static let dachenPhonabetMap: [Unicode.Scalar: Unicode.Scalar] = [
    "0": "ㄢ", "1": "ㄅ", "2": "ㄉ", "3": "ˇ", "4": "ˋ", "5": "ㄓ", "6": "ˊ", "7": "˙", "8": "ㄚ",
    "9": "ㄞ", "-": "ㄦ", ",": "ㄝ", ".": "ㄡ", "/": "ㄥ", ";": "ㄤ", "a": "ㄇ", "b": "ㄖ",
    "c": "ㄏ", "d": "ㄎ", "e": "ㄍ", "f": "ㄑ", "g": "ㄕ", "h": "ㄘ", "i": "ㄛ", "j": "ㄨ",
    "k": "ㄜ", "l": "ㄠ", "m": "ㄩ", "n": "ㄙ", "o": "ㄟ", "p": "ㄣ", "q": "ㄆ", "r": "ㄐ",
    "s": "ㄋ", "t": "ㄔ", "u": "ㄧ", "v": "ㄒ", "w": "ㄊ", "x": "ㄌ", "y": "ㄗ", "z": "ㄈ", " ": " ",
  ]
}
