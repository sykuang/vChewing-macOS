# Mixed English Dictionary Boundary Protection Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Add a lightweight English dictionary signal for vChewing mixed alphanumerical input so completed English words such as `hell ` can be protected from accidental tail terminal conversion (`l␠ -> ㄠ/坳`) without restoring whole-buffer fallback, prefix/suffix scans, ranking, recommendation UI, or spellcheck ownership.

**Architecture:** Keep `MixedInputSegmentStream` as the display/commit source of truth. Add a small `EnglishWordLexicon` service in Typewriter that answers exact-word queries for the current active raw segment only. The dictionary is a segment-local terminal-conversion veto: if the active raw segment ends in ASCII whitespace and the immediately completed English token is an exact dictionary match, do not peel the trailing key+space as a phonetic terminal. The first implementation should be offline, deterministic, user-importable or bundled with a license-clean dictionary, and testable without AppKit.

**Tech Stack:** Swift 6.2, SwiftPM resources or user-imported dictionary file, Typewriter package tests. `NSSpellChecker` is not part of core tests because its behavior is system/user-language dependent.

---

## Product rule / non-goals

- Do **not** revive `applyWholeRawBufferCommitIfReady`, `isUnsafeWholeRawBufferCommit`, whole-buffer promotion, whole-word spellcheck ownership, candidate recommendation UI, ranking UI, or suffix scanning over historical raw text.
- Dictionary lookup may inspect only the **current active raw segment** exposed by `mixedInputSegmentStream.activeRawText` / `activeRawBuffer`.
- Dictionary lookup is **exact completed-token match only**. It is not autocomplete, not fuzzy correction, and not candidate ranking.
- Chinese/phonetic conversion remains segment-local terminal replacement unless the active raw segment ends with whitespace after an exact English word match.
- English dictionary is a **terminal-conversion veto signal** only. It should not silently commit English text or steal Space/Enter ownership.
- Product example: `hell ` should remain raw if `hell` exists in the enabled English dictionary; `l ` alone may still become `ㄠ/坳` because the completed token `l` is not a protected English word.

## Licensing / user-downloaded dictionary rule

- Letting users download/import a dictionary can reduce redistribution risk because vChewing would not ship the third-party data itself.
- It does **not** erase license duties entirely: the UI must show the dictionary source/license, avoid bundling/sharealike data in the app, and avoid auto-downloading from a source whose terms forbid that use.
- Safest structure: ship only parser + importer + empty/default minimal allowlist; provide documentation with links to compatible dictionaries; when user imports, store locally under Application Support and record source/license metadata.
- If vChewing provides a one-click downloader, that is closer to redistribution/facilitation; still needs per-source license review and attribution.

## UX phases

1. **Phase 1 — local dictionary import + exact-match boundary veto**
   - User imports a newline/Hunspell `.dic` word list.
   - On Space, if active raw segment becomes something like `hell ` and `hell` exact-matches dictionary, skip terminal peeling of `l␠`.
   - No tooltip recommendation, no ranking, no autocomplete.
2. **Phase 2 — optional bundled license-clean dictionary**
   - If we later choose SCOWL/Hunspell MIT/BSD-compatible source, bundle it with attribution.
   - Same exact-match behavior; no ranking.
3. **Phase 3 — optional typo correction**
   - Only if wanted later, evaluate `SymSpellSwift` for typo correction. Not part of current scope.

## Recommended dictionary for this exact-match plan

For this plan, the best default recommendation is **SCOWL-derived Hunspell English**, preferably `wooorm/dictionaries` English package or `facelessuser/hunspell-en-us`.

### Primary recommendation: `wooorm/dictionaries` / `dictionary-en`

- Repo: https://github.com/wooorm/dictionaries
- English license/readme: https://raw.githubusercontent.com/wooorm/dictionaries/main/dictionaries/en/license
- English `.dic`: https://raw.githubusercontent.com/wooorm/dictionaries/main/dictionaries/en/index.dic
- Why it fits this plan:
  - Exact word existence check only; no frequency/ranking needed.
  - English package is listed as `(MIT AND BSD)` in the repo summary; SCOWL license text allows use/copy/modify/distribute/sell with notices.
  - Hunspell `.dic` already encodes accepted English stems/forms; we can strip affix flags after `/` and use the base token set.
  - Around 49k entries, enough to catch `hell`, `film`, `what`, etc. without bundling huge frequency corpora.
- Implementation note:
  - Ignore first count line.
  - For each line, strip after `/` to remove Hunspell flags.
  - Lowercase ASCII words.
  - Exclude one-letter tokens by default (`a` and `i` are common English words but protecting them would conflict with phonetic typing too often); optionally allow a curated exception list later.
  - Exact match only on completed token before trailing whitespace.

### Secondary recommendation: `facelessuser/hunspell-en-us`

- Repo: https://github.com/facelessuser/hunspell-en-us
- README/license/source: https://raw.githubusercontent.com/facelessuser/hunspell-en-us/master/README_en_US.txt
- Why it fits:
  - Also SCOWL-derived English US Hunspell dictionary.
  - Good if we want a smaller/direct repo with `en_US.dic` / `en_US.aff`.

### Avoid for this plan

- `first20hours/google-10000-english`: license warns against commercial use without LDC license.
- `aparrish/wordfreq-en-25000` and `hermitdave/FrequencyWords`: CC-BY-SA data; unnecessary because no ranking/frequency is needed.
- `filiph/english_words`: MIT and useful, but only ~5000 words and frequency-oriented; less complete than SCOWL for exact-match protection.
- `SymSpellSwift`: useful later for typo correction, but not needed for exact dictionary match.

---



**Objective:** Define the expected lookup behavior before adding production code.

**Files:**
- Create: `Packages/vChewing_Typewriter/Tests/TypewriterTests/EnglishWordLexiconTests.swift`
- Later create: `Packages/vChewing_Typewriter/Sources/Typewriter/InputHandler/EnglishWordLexicon.swift`

**Step 1: Write failing tests**

```swift
import Testing
@testable import Typewriter

@Suite(.serialized)
struct EnglishWordLexiconTests {
  @Test
  func exactWordLookupIsCaseInsensitive() {
    let lexicon = EnglishWordLexicon(words: [
      .init(word: "hello", frequency: 100),
      .init(word: "hell", frequency: 50),
    ])

    #expect(lexicon.containsExactWord("hello"))
    #expect(lexicon.containsExactWord("Hello"))
    #expect(!lexicon.containsExactWord("hel"))
  }

  @Test
  func prefixSuggestionsAreFrequencySortedAndLimited() {
    let lexicon = EnglishWordLexicon(words: [
      .init(word: "help", frequency: 40),
      .init(word: "hello", frequency: 100),
      .init(word: "hell", frequency: 60),
      .init(word: "helmet", frequency: 10),
    ])

    #expect(lexicon.suggestions(forPrefix: "hel", limit: 3).map(\.word) == ["hello", "hell", "help"])
  }

  @Test
  func lookupIgnoresNonEnglishRawSegments() {
    let lexicon = EnglishWordLexicon(words: [.init(word: "hello", frequency: 100)])

    #expect(lexicon.suggestions(forPrefix: "hel5", limit: 3).isEmpty)
    #expect(lexicon.suggestions(forPrefix: "你好", limit: 3).isEmpty)
    #expect(lexicon.suggestions(forPrefix: "he-", limit: 3).isEmpty)
  }
}
```

**Step 2: Run to verify failure**

```bash
cd /Users/kenkuang/src/vChewing-macOS/Packages/vChewing_Typewriter
swift test --filter EnglishWordLexiconTests
```

Expected: fail because `EnglishWordLexicon` does not exist.

---

## Task 2: Implement in-memory `EnglishWordLexicon`

**Objective:** Add a tiny deterministic dictionary structure with exact and prefix lookup.

**Files:**
- Create: `Packages/vChewing_Typewriter/Sources/Typewriter/InputHandler/EnglishWordLexicon.swift`

**Implementation sketch:**

```swift
// (c) 2021 and onwards The vChewing Project (MIT-NTL License).

import Foundation

public struct EnglishWordLexicon: Sendable {
  public struct Entry: Hashable, Sendable {
    public let word: String
    public let frequency: Int

    public init(word: String, frequency: Int) {
      self.word = word.lowercased()
      self.frequency = frequency
    }
  }

  private let entries: [Entry]
  private let exactWords: Set<String>

  public init(words: [Entry]) {
    let normalized = words
      .filter { Self.isASCIIWord($0.word) }
      .sorted { lhs, rhs in
        if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
        return lhs.word < rhs.word
      }
    self.entries = normalized
    self.exactWords = Set(normalized.map(\.word))
  }

  public func containsExactWord(_ text: String) -> Bool {
    exactWords.contains(text.lowercased())
  }

  public func suggestions(forPrefix prefix: String, limit: Int = 5) -> [Entry] {
    let normalizedPrefix = prefix.lowercased()
    guard limit > 0, Self.isASCIIWord(normalizedPrefix) else { return [] }
    return Array(entries.lazy.filter { $0.word.hasPrefix(normalizedPrefix) }.prefix(limit))
  }

  public static func isASCIIWord(_ text: String) -> Bool {
    guard !text.isEmpty else { return false }
    return text.unicodeScalars.allSatisfy { scalar in
      scalar.isASCII && CharacterSet.letters.contains(scalar)
    }
  }
}
```

**Step 2: Verify**

```bash
swift test --filter EnglishWordLexiconTests
```

Expected: pass.

---

## Task 3: Add bundled minimal word list loader

**Objective:** Make production code load an offline dictionary resource without depending on system spellchecker.

**Files:**
- Modify: `Packages/vChewing_Typewriter/Package.swift`
- Create: `Packages/vChewing_Typewriter/Sources/Typewriter/Resources/EnglishWords.tsv`
- Modify: `EnglishWordLexicon.swift`
- Test: `EnglishWordLexiconTests.swift`

**Resource format:**

```text
hello	100000
help	80000
hell	30000
helmet	12000
the	200000
what	150000
```

**Package.swift change:**

```swift
.target(
  name: "Typewriter",
  dependencies: [...],
  resources: [
    .process("Resources"),
  ],
  swiftSettings: [
    .defaultIsolation(MainActor.self),
  ],
  linkerSettings: [
    .linkedLibrary("iconv", .when(platforms: [.macOS])),
  ]
)
```

**Loader API sketch:**

```swift
public static func bundled() -> EnglishWordLexicon {
  guard let url = Bundle.module.url(forResource: "EnglishWords", withExtension: "tsv"),
        let content = try? String(contentsOf: url, encoding: .utf8) else {
    return EnglishWordLexicon(words: [])
  }
  return EnglishWordLexicon(words: parseTSV(content))
}

static func parseTSV(_ content: String) -> [Entry] {
  content.split(whereSeparator: \.isNewline).compactMap { line in
    let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
    guard fields.count == 2, let freq = Int(fields[1]) else { return nil }
    return Entry(word: fields[0], frequency: freq)
  }
}
```

**Tests:**

- `parseTSVIgnoresMalformedLines`
- `bundledLexiconContainsCommonWords`

**Verification:**

```bash
swift test --filter EnglishWordLexiconTests
swift test --filter 'MixedInputRawBufferTests|MixedInputSegmentStreamTests|IH405|IH408|IH410|IH411|IH419|IH425'
```

---

## Task 4: Add active-segment English suggestion helper

**Objective:** Keep dictionary lookup scoped to the current active raw segment.

**Files:**
- Modify: `InputHandler_CoreProtocol.swift`
- Create/Modify: `InputHandler_MixedEnglishSuggestions.swift` or `InputHandler_HandleStates.swift`
- Test: `InputHandlerTests_Cases4.swift`

**API shape:**

```swift
extension InputHandlerProtocol {
  public func mixedEnglishSuggestions(limit: Int = 3) -> [EnglishWordLexicon.Entry] {
    let raw = mixedInputSegmentStream.activeRawText
    guard raw.count >= 2 else { return [] }
    return EnglishWordLexicon.bundled().suggestions(forPrefix: raw, limit: limit)
  }
}
```

**Important:** In final implementation, avoid reloading `Bundle.module` on every keypress. Add a static cached lexicon, e.g. `EnglishWordLexicon.Shared.default`.

**Tests:**

- Given stream `raw("hel")`, suggestions include `hello`.
- Given stream `raw("Y") + chinese("軸")`, suggestions are empty because active raw is empty.
- Given stream `chinese("你好") + raw("te")`, suggestions use only `te`, not `你好te`.

---

## Task 5: Surface suggestions without changing commit semantics

**Objective:** Show English suggestions in UI diagnostics while leaving commit/conversion behavior unchanged.

**Files:**
- Modify: `InputHandler_HandleStates.swift:generateStateOfInputting`
- Test: existing mixed tooltip tests or new `IH44x`.

**Policy:**

- If active Trie phonabet exists, keep it first.
- Append English suggestions only as passive hint.
- Example tooltip: `ㄠ · hell/hello/help`.
- If no Trie phonabet exists but English suggestions exist, tooltip may be `hello/help`.

**Tests:**

- `hel` shows English suggestions.
- `Y5.6` after conversion shows no English suggestion for sealed `Y`.
- `5 ` still shows/converts `之`; English suggestions do not interfere.

---

## Task 6: Candidate-window English replacement (optional second PR)

**Objective:** Allow user to select an English completion candidate that replaces the active raw segment only.

**Files:**
- Modify candidate generation in `InputHandler_HandleStates.swift`
- Add stream helper in `MixedInputSegmentStream.swift`:
  - `replacingActiveRaw(with text: String) -> MixedInputSegmentStream`
- Add confirm handling if candidate type needs metadata.

**Tests:**

- `你好te` + select `test` → `你好test`.
- `Y5.6` remains `Y軸`; English candidate does not rewrite sealed raw `Y`.
- Candidate abort/reset commits canonical stream exactly once.

---

## Task 7: Arbitration experiments (only after UI signal is stable)

**Objective:** Use dictionary confidence to tune terminal conversion without breaking current-segment rules.

**Possible rules to test:**

- Exact common English word + trailing Space should prefer raw English unless user explicitly selects Zhuyin candidate.
- Prefix-only should not block terminal conversion by itself.
- Very short active segment (`l␠`) remains allowed unless皇上 changes product rule.

**Required regression set:**

```bash
swift test --filter 'EnglishWordLexiconTests|MixedInputRawBufferTests|MixedInputSegmentStreamTests|IH405|IH408|IH410|IH411|IH419|IH425|IH43'
swift test
```

Then rebuild/install and replay live with CGEvent + Peekaboo.

---

## Open questions before implementation

1. Dictionary source: use a tiny bundled list first, or import a larger word-frequency list? If larger, confirm license compatibility.
2. UX: should English suggestions appear in tooltip only, or candidate window too?
3. Arbitration: should dictionary ever block terminal conversion automatically, or only reorder/recommend?
4. Personalization: should accepted English words be learned later, or stay static for now?
