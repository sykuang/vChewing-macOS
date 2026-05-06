// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation
import Tekkon

// MARK: - ZhuyinKeyTrie

/// A prefix trie of all valid key sequences that produce toned Zhuyin syllables.
/// Used to determine if a given key sequence can continue as Zhuyin or is dead.
///
/// Built from dictionary-derived terminal data (1672 actual readings, ~8KB).
/// Each entry is a complete key sequence including tone key.
public final class ZhuyinKeyTrie: @unchecked Sendable {

  // MARK: - TrieNode

  private final class TrieNode {
    let id: Int
    var children: [Character: TrieNode] = [:]
    var isTerminal: Bool = false

    init(id: Int) {
      self.id = id
    }
  }

  // MARK: - Cursor

  /// Opaque handle for an incremental trie traversal position.
  ///
  /// Callers store this in their own per-key frame stack. Backspace is then a
  /// plain frame pop: no full-buffer suffix re-scan is needed to recover the
  /// previous parent state.
  public struct Cursor: Equatable, Sendable {
    fileprivate let nodeID: Int
  }

  // MARK: - Singleton per parser

  private static let lock = NSLock()
  private static var instances: [Tekkon.MandarinParser: ZhuyinKeyTrie] = [:]

  public static func shared(for parser: Tekkon.MandarinParser) -> ZhuyinKeyTrie {
    lock.lock()
    defer { lock.unlock() }
    if let existing = instances[parser] { return existing }
    let trie = ZhuyinKeyTrie(parser: parser)
    instances[parser] = trie
    return trie
  }

  // MARK: - Properties

  private let root: TrieNode
  private var nodes: [TrieNode] = []
  public private(set) var terminalCount = 0

  public var rootCursor: Cursor { .init(nodeID: root.id) }

  // MARK: - Init

  private init(parser: Tekkon.MandarinParser) {
    self.root = TrieNode(id: 0)
    self.nodes = [root]
    loadPrecomputedData(parser: parser)
  }

  private func makeNode() -> TrieNode {
    let node = TrieNode(id: nodes.count)
    nodes.append(node)
    return node
  }

  /// Load trie from dictionary-derived terminal data.
  /// Each line is a complete key sequence (including tone key).
  private func loadPrecomputedData(parser: Tekkon.MandarinParser) {
    let rawData: String
    switch parser {
    case .ofDachen:
      rawData = Self.dachenTerminalData
    default:
      assertionFailure("ZhuyinKeyTrie: no precomputed data for parser \(parser)")
      return
    }

    for line in rawData.split(separator: "\n", omittingEmptySubsequences: true) {
      let normalizedLine = line.replacingOccurrences(of: "␠", with: " ")
      var node = root
      for ch in normalizedLine {
        if node.children[ch] == nil {
          node.children[ch] = makeNode()
        }
        node = node.children[ch]!
      }
      if !node.isTerminal {
        node.isTerminal = true
        terminalCount += 1
      }
    }
  }

  // MARK: - Public API

  public enum AdvanceResult: Equatable, Sendable {
    case prefix
    case terminal
    case dead
  }

  private func state(of node: TrieNode) -> AdvanceResult {
    if node.isTerminal { return .terminal }
    if !node.children.isEmpty { return .prefix }
    return .dead
  }

  /// Incrementally advance from a stored trie cursor with one new key.
  ///
  /// The returned cursor is the child node for live states. Store it in a frame
  /// stack together with the raw key; backspace restores the parent simply by
  /// popping the last frame.
  public func advance(from cursor: Cursor, with key: String) -> (cursor: Cursor?, state: AdvanceResult) {
    guard let character = key.first, key.count == 1, nodes.indices.contains(cursor.nodeID) else {
      return (nil, .dead)
    }
    let node = nodes[cursor.nodeID]
    guard let child = node.children[character] else { return (nil, .dead) }
    return (.init(nodeID: child.id), state(of: child))
  }

  /// Check an existing key sequence against the trie.
  ///
  /// - Parameter keys: The key sequence to inspect (e.g. `["t", "e", "s"]`).
  /// - Returns: `.prefix` if the sequence can still continue as Zhuyin, `.terminal`
  ///   if it already forms a complete toned syllable, or `.dead` if it cannot match.
  public func state(for keys: [String]) -> AdvanceResult {
    guard !keys.isEmpty else { return .prefix }
    var cursor = rootCursor
    var result: AdvanceResult = .prefix
    for k in keys {
      let advanced = advance(from: cursor, with: k)
      guard let nextCursor = advanced.cursor else { return .dead }
      cursor = nextCursor
      result = advanced.state
    }
    return result
  }

  /// Check if appending `key` to an existing key sequence can continue as Zhuyin.
  ///
  /// - Parameters:
  ///   - keys: The existing key sequence (e.g. `["v", "p"]`).
  ///   - key: The new key to append.
  /// - Returns: `.prefix` if the sequence can continue, `.terminal` if it forms a
  ///   complete toned syllable, or `.dead` if the sequence is invalid.
  public func advance(from keys: [String], with key: String) -> AdvanceResult {
    state(for: keys + [key])
  }
}
