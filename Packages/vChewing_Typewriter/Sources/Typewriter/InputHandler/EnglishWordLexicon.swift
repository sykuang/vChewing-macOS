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
    var union = Set<String>()
    union.reserveCapacity(60_000)
    for source in Self.bundledDictionarySources {
      guard let url = Self.bundledDictionaryURL(
        subdirectory: source.subdirectory,
        fileStem: source.fileStem
      ),
        let text = try? String(contentsOf: url, encoding: .utf8)
      else { continue }
      switch source.parser {
      case .hunspell: union.formUnion(Self.parseHunspellDictionary(text))
      case .plain: union.formUnion(Self.parsePlainWordlist(text))
      }
    }
    self.init(words: union)
  }

  /// Bundled dictionary sources: wooorm `index.dic`（Hunspell 格式，
  /// ≈49K natural English stems）為基底；`tech-supplemental/tech.dic`
  /// 補上 `npm` / `json` / `k8s` 等 wooorm 沒收的現代技術縮寫。
  ///
  /// 為什麼不用 SCOWL 60+hacker：實測它把 `hellos` / `tests` 這類字尾
  /// 變化形也收進來，導致 oracle 在「打完 `hello` 接 `s` 想轉注音」時
  /// 把 `s` 留給英文，使用體驗大幅變糟。wooorm 的 Hunspell stem 表
  /// 把字尾變化交給 affix 規則處理、本身較精簡，誤殺面遠小。
  ///
  /// Filenames are intentionally distinct（`index.dic`、`tech.dic`）以
  /// 避免 SwiftPM 拒收同名 resource。
  private static var bundledDictionarySources: [(subdirectory: String, fileStem: String, parser: WordlistParserKind)] {
    [
      ("EnglishDictionaries/wooorm-dictionaries-en", "index", .hunspell),
      ("EnglishDictionaries/tech-supplemental", "tech", .plain),
    ]
  }

  /// Bundled wordlist 的 parser 種類。
  /// - `.hunspell`: stems followed by `/AFFIX` codes (wooorm `index.dic`)。
  /// - `.plain`: one bare token per line, `#`-prefixed comments allowed
  ///   (tech-supplemental)。
  private enum WordlistParserKind: Sendable {
    case hunspell, plain
  }

  /// 解析 plain wordlist：每行一個 token，`#` 起頭與含空白的行皆略過——
  /// 讓使用者手動編輯的 supplemental 檔可以放註解、分區標題。
  public static func parsePlainWordlist(_ text: String) -> Set<String> {
    var parsed = Set<String>()
    parsed.reserveCapacity(2_000)
    text.enumerateLines { line, _ in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return }
      guard !trimmed.contains(" ") else { return }
      guard let normalized = normalizedToken(trimmed) else { return }
      parsed.insert(normalized)
    }
    return parsed
  }

  private static func bundledDictionaryURL(subdirectory: String, fileStem: String) -> URL? {
    let bundleName = "Typewriter_Typewriter"
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
      if let url = bundle.url(forResource: fileStem, withExtension: "dic")
        ?? bundle.url(forResource: fileStem, withExtension: "dic", subdirectory: subdirectory)
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
