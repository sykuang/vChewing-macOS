# tech-supplemental wordlist

vChewing 自訂的技術詞彙補充清單，與 SCOWL 主字典 OR 起來，
用來阻止 Mixed-input Trie 把英文字 / 縮寫切開（例如 `npm + j6`
原本會把 `npm` 的 `m` 跟 `j6` 黏成漢字）。

格式：每行一個 stem，`#` 開頭與空行為註解。所有詞會 lower-case
後當 exact-match token 比對。

加詞規則：
- 在 mixed mode 真的遇到「英文字 / 縮寫被切開」才加。
- 短詞（`<3` 字元）會被 `tokenSplitByTerminalSuffix` helper 自己擋住。
- 命名衝突或可能造成誤殺時請優先補測試（IH438 系列）。

授權：本檔內容為純詞彙列表，使用上比照 `LICENSE`（MIT-NTL，
與 vChewing 主 repo 一致）。
