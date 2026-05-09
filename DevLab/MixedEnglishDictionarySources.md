# English Dictionary Sources for Mixed Input Recommendation

皇上需求：先找到可用英文字典來源；優先 Swift Package 或 open-source corpus，目標是支援 vChewing mixed alphanumerical input 的英文推薦，不要先動 commit FSM。

## 評估結論（2026-05-08）

首選分成兩層：

1. **演算法 / Swift package：`gdetari/SymSpellSwift`**
   - URL: https://github.com/gdetari/SymSpellSwift
   - License: MIT（https://raw.githubusercontent.com/gdetari/SymSpellSwift/main/LICENSE）
   - SwiftPM: 有 `Package.swift`，library product `SymSpellSwift`，platform `.macOS(.v12)` / `.iOS(.v15)`。
   - 功能：SymSpell spelling correction / fuzzy search / lookupCompound / word segmentation。
   - 適合：日後要 typo correction / fuzzy suggestion 時用。
   - 注意：vChewing 目前 Typewriter package platform 是 macOS 11；若直接依賴，需確認能不能降 platform 到 macOS 11，或只借鑑資料結構自己實作 prefix trie。
   - 不適合作為唯一 Phase 1：它是演算法，不是字典資料；仍需要 frequency dictionary。

2. **字典資料首選：SCOWL / Hunspell English dictionary via `wooorm/dictionaries` 或 `facelessuser/hunspell-en-us`**
   - wooorm dictionaries: https://github.com/wooorm/dictionaries
   - English package license 摘要：`dictionary-en` 為 `(MIT AND BSD)`；但需保留各 dictionary license。來源說明：https://raw.githubusercontent.com/wooorm/dictionaries/main/dictionaries/en/license
   - English `index.dic`: https://raw.githubusercontent.com/wooorm/dictionaries/main/dictionaries/en/index.dic
   - facelessuser mirror: https://github.com/facelessuser/hunspell-en-us
   - facelessuser README/license/source: https://raw.githubusercontent.com/facelessuser/hunspell-en-us/master/README_en_US.txt
   - 優點：授權比 CC-BY-SA 類 frequency corpus 乾淨，適合隨 app 發佈；約 49k entries，含 affix flags，可先抽 stem/base forms。
   - 缺點：不是 frequency ranked；需要另外排序或只做 exact/prefix validity。

## 備選資料源

### `filiph/english_words`
- URL: https://github.com/filiph/english_words
- License: MIT（https://raw.githubusercontent.com/filiph/english_words/master/LICENSE）
- 內容：約 5000 常用英文詞 + Dart utility，資料檔 `data/word-freq-top5000.csv` 有 rank/frequency/POS。
- 優點：授權乾淨、帶 frequency、大小適合 IME 即時 prefix suggestion。
- 缺點：不是 Swift package，是 Dart package；需抽資料成 TSV/resource。
- 適合：Phase 1 的 frequency-ranked suggestion seed list。

### `aparrish/wordfreq-en-25000`
- URL: https://github.com/aparrish/wordfreq-en-25000
- README/license: https://raw.githubusercontent.com/aparrish/wordfreq-en-25000/main/README.md
- 內容：wordfreq 匯出的 25k English words + log frequency。
- License：CC-BY-SA-4.0（繼承 wordfreq data）。
- 優點：品質好、帶 frequency。
- 風險：ShareAlike 對 vChewing 發佈與資料再散佈可能麻煩；不建議首選。

### `hermitdave/FrequencyWords`
- URL: https://github.com/hermitdave/FrequencyWords
- README: https://github.com/hermitdave/FrequencyWords
- License file: https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/LICENSE
- README 說明：code MIT；content CC-BY-SA-4.0；OpenSubtitles corpus；format `{word} {count}`。
- 優點：有大量 frequency list，輸入法/keyboard 類專案常用。
- 風險：content CC-BY-SA-4.0；若要 bundle 進 vChewing，要先確認相容性。

### `first20hours/google-10000-english`
- URL: https://github.com/first20hours/google-10000-english
- License: https://raw.githubusercontent.com/first20hours/google-10000-english/master/LICENSE.md
- License 明確說不建議 commercial use without LDC license；只允許 educational/personal/research under LDC/Norvig/fair use。
- 結論：不適合 bundle 進 vChewing 發佈。

### Apple `NSSpellChecker`
- URL: https://developer.apple.com/documentation/appkit/nsspellchecker
- 優點：macOS 內建；可查拼字/建議。
- 缺點：AppKit/service dependency、行為受系統語言與使用者字典影響、測試不 deterministic；Typewriter core 目前不宜直接依賴。
- 適合：未來 provider wrapper / optional runtime hint，不適合作為 core deterministic dictionary。

## 推薦 Phase 1 組合

最安全務實：

- **Base validity dictionary**：SCOWL/Hunspell `dictionary-en/index.dic`（MIT/BSD-style licensing，需保存 attribution/license）。
- **Frequency ordering**：先用 `filiph/english_words` top 5000（MIT）當 ranking overlay；若詞在 frequency list 內就按 frequency 排，否則 fallback alphabetical 或 low score。
- **Swift implementation**：先自己寫 `EnglishWordLexicon`（prefix trie / sorted array）以避免 macOS 12 dependency；`SymSpellSwift` 留給 Phase 2 typo correction 評估。

這樣可滿足：
- open-source
- license clean enough for bundling（需最終 legal check）
- deterministic unit tests
- 不引入 whole-buffer fallback
- 不依賴 AppKit spell checker

## 來源 URL 清單

- SymSpellSwift: https://github.com/gdetari/SymSpellSwift
- SymSpellSwift Package.swift: https://raw.githubusercontent.com/gdetari/SymSpellSwift/main/Package.swift
- SymSpellSwift MIT license: https://raw.githubusercontent.com/gdetari/SymSpellSwift/main/LICENSE
- wooorm/dictionaries: https://github.com/wooorm/dictionaries
- wooorm English license: https://raw.githubusercontent.com/wooorm/dictionaries/main/dictionaries/en/license
- wooorm English dic: https://raw.githubusercontent.com/wooorm/dictionaries/main/dictionaries/en/index.dic
- facelessuser/hunspell-en-us: https://github.com/facelessuser/hunspell-en-us
- facelessuser README/license/source: https://raw.githubusercontent.com/facelessuser/hunspell-en-us/master/README_en_US.txt
- filiph/english_words: https://github.com/filiph/english_words
- filiph MIT license: https://raw.githubusercontent.com/filiph/english_words/master/LICENSE
- wordfreq-en-25000: https://github.com/aparrish/wordfreq-en-25000
- wordfreq-en-25000 README/license: https://raw.githubusercontent.com/aparrish/wordfreq-en-25000/main/README.md
- hermitdave/FrequencyWords: https://github.com/hermitdave/FrequencyWords
- hermitdave license: https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/LICENSE
- google-10000 license: https://raw.githubusercontent.com/first20hours/google-10000-english/master/LICENSE.md
- Apple NSSpellChecker: https://developer.apple.com/documentation/appkit/nsspellchecker
