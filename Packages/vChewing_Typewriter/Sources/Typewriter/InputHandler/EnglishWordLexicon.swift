// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation

// MARK: - EnglishWordLexicon

/// Exact-match English word lexicon for mixed-input boundary protection.
///
/// This type intentionally does **not** implement suggestions, ranking,
/// spell-checking, affix expansion, or autocomplete.  It only answers whether a
/// completed ASCII token is an exact dictionary word so mixed mode can veto a
/// terminal Zhuyin conversion at the word boundary.
public struct EnglishWordLexicon: Sendable {
  public static let bundled = EnglishWordLexicon(contentsOfBundledDictionary: ())

  private let words: Set<String>

  public init(words: Set<String>) {
    self.words = words
  }

  public init(hunspellDictionaryText text: String) {
    self.init(words: Self.parseHunspellDictionary(text))
  }

  public var count: Int { words.count }

  public func containsExactToken(_ token: String) -> Bool {
    guard let normalized = Self.normalizedToken(token) else { return false }
    return words.contains(normalized)
  }

  public static func completedASCIIToken(beforeTrailingBoundary rawText: String) -> String? {
    guard rawText.last?.isASCIIWordBoundary == true else { return nil }
    let tokenEnd = rawText.index(before: rawText.endIndex)
    var tokenStart = tokenEnd
    while tokenStart > rawText.startIndex {
      let previousIndex = rawText.index(before: tokenStart)
      guard rawText[previousIndex].isASCIIWordToken else { break }
      tokenStart = previousIndex
    }
    guard tokenStart < tokenEnd else { return nil }
    let token = String(rawText[tokenStart ..< tokenEnd])
    guard token.count >= 3, normalizedToken(token) != nil else { return nil }
    return token
  }

  public static func parseHunspellDictionary(_ text: String) -> Set<String> {
    var parsed = Set<String>()
    parsed.reserveCapacity(50_000)

    text.enumerateLines { line, _ in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { return }
      if parsed.isEmpty, Int(trimmed) != nil { return }
      guard let stem = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first else {
        return
      }
      guard let normalized = normalizedToken(String(stem)) else { return }
      parsed.insert(normalized)
    }
    return parsed
  }

  private init(contentsOfBundledDictionary _: Void) {
    guard let url = Bundle.module.url(forResource: "index", withExtension: "dic")
      ?? Bundle.module.url(
        forResource: "index",
        withExtension: "dic",
        subdirectory: "EnglishDictionaries/wooorm-dictionaries-en"
      ),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      self.init(words: [])
      return
    }
    self.init(hunspellDictionaryText: text)
  }

  private static func normalizedToken(_ token: String) -> String? {
    let normalized = token.lowercased()
    guard !normalized.isEmpty else { return nil }
    guard normalized.unicodeScalars.allSatisfy({ scalar in
      scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "-")
    }) else { return nil }
    guard normalized.unicodeScalars.contains(where: { scalar in
      scalar.isASCII && CharacterSet.letters.contains(scalar)
    }) else { return nil }
    return normalized
  }
}

private extension Character {
  var isASCIIWordToken: Bool {
    unicodeScalars.count == 1 && unicodeScalars.allSatisfy { scalar in
      scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "'" || scalar == "-")
    }
  }

  var isASCIIWordBoundary: Bool {
    unicodeScalars.count == 1 && unicodeScalars.allSatisfy { scalar in
      scalar.isASCII && CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
  }
}
