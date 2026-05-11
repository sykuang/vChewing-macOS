// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// ====================
// This code is released under the MIT license (SPDX-License-Identifier: MIT)
// ... with NTL restriction stating that:
// No trademark license is granted to use the trade names, trademarks, service
// marks, or product names of Contributor, except as required to fulfill notice
// requirements defined in MIT License.

import Foundation

private final class TypewriterBundleFinder {}

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

  /// 給定 `rawText` 與 `suffixStart`（active suffix 在 rawText 中的字元起點 offset），
  /// 若該 offset 落在已存在的 ASCII word run 內，回傳「會被切開的完整 token」
  /// （prefix run + suffixStart 該 char 自身），供 caller 查字典 veto。
  ///
  /// 條件：
  /// - `suffixStart` 落在 `[1, rawText.count - 1]`（首字元無前綴可切開）。
  /// - `suffixStart` 與其前一字元皆為 ASCII word char（letters/digits/'-'/'\''）。
  /// - 結果 token ≥ 3 char、normalize 後合法。
  ///
  /// 例：`rawText="privatej6"`, `suffixStart=6`（`e` 的位置）→ "private"。
  public static func tokenSplitByTerminalSuffix(
    rawText: String,
    suffixStart: Int
  ) -> String? {
    let chars = Array(rawText)
    guard suffixStart >= 1, suffixStart < chars.count else { return nil }
    guard chars[suffixStart].isASCIIWordToken else { return nil }
    guard chars[suffixStart - 1].isASCIIWordToken else { return nil }
    var tokenStart = suffixStart
    while tokenStart > 0, chars[tokenStart - 1].isASCIIWordToken {
      tokenStart -= 1
    }
    let token = String(chars[tokenStart ... suffixStart])
    guard token.count >= 3, normalizedToken(token) != nil else { return nil }
    return token
  }

  /// 上一版的便利包裝：用 `suffix` 字串推算 `suffixStart` 後委派給上方主 API。
  /// 保留給「拿到完整 commit」場景的 caller。
  public static func tokenSplitByTerminalSuffix(
    rawText: String,
    suffix: String
  ) -> String? {
    guard !suffix.isEmpty, rawText.hasSuffix(suffix) else { return nil }
    let suffixStart = rawText.count - suffix.count
    return tokenSplitByTerminalSuffix(rawText: rawText, suffixStart: suffixStart)
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
    guard let url = Self.bundledDictionaryURL(),
          let text = try? String(contentsOf: url, encoding: .utf8)
    else {
      self.init(words: [])
      return
    }
    self.init(hunspellDictionaryText: text)
  }

  private static func bundledDictionaryURL() -> URL? {
    let bundleName = "Typewriter_Typewriter"
    let resourcePath = "EnglishDictionaries/wooorm-dictionaries-en"
    let finderBundle = Bundle(for: TypewriterBundleFinder.self)
    let candidates: [URL?] = [
      // Installed .app: SwiftPM resource bundles are copied to Contents/Resources/.
      Bundle.main.resourceURL,
      // Framework/test embedding.
      finderBundle.resourceURL,
      finderBundle.bundleURL.deletingLastPathComponent(),
      // SwiftPM command-line/test build directory fallbacks.
      Bundle.main.bundleURL,
      Bundle.main.bundleURL.deletingLastPathComponent(),
    ]
    for candidate in candidates {
      guard let bundleURL = candidate?.appendingPathComponent(bundleName + ".bundle"),
            let bundle = Bundle(url: bundleURL) else { continue }
      if let url = bundle.url(forResource: "index", withExtension: "dic")
        ?? bundle.url(forResource: "index", withExtension: "dic", subdirectory: resourcePath)
      {
        return url
      }
    }
    return nil
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
