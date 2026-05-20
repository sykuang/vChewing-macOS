// (c) 2021 and onwards The vChewing Project (MIT-NTL License).
// Spike + regression tests for A3-style "insert at cursor" semantics on
// MixedInputSegmentStream.

import Tekkon
import Testing
@testable import Typewriter

@Suite("MixedInputSegmentStream_InsertAtCursorTests", .serialized)
struct MixedInputSegmentStream_InsertAtCursorTests {
  typealias Seg = MixedInputSegmentStream.Segment

  private static let conversions: [String: (text: String, readings: [String])] = [
    "su3": ("你", ["ㄋㄧˇ"]),
    "cl3": ("好", ["ㄏㄠˇ"]),
    "5.6": ("軸", ["ㄓㄡˊ"]),
    "xul3": ("了", ["ㄌㄧㄠˇ"]),
  ]

  private static func type(
    _ input: String,
    into stream: inout MixedInputSegmentStream
  ) {
    for key in input.map(\.description) {
      let commit = stream.appendRawKey(key)
      guard let commit, let conversion = conversions[commit.suffix],
            let replacement = stream.chineseReplacement(
              for: commit,
              chineseText: conversion.text,
              readings: conversion.readings,
              acceptsLeadingIntonation: true
            )
      else { continue }
      stream.replaceActiveRawWithChinese(replacement)
    }
  }

  // MARK: - Case 1: cursor inside raw segment → freeze + new active raw segment

  @Test
  func insertRawKey_insideRawSegment_createsNewActiveSegment() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendRaw("hello")
    // Move cursor to position 2 (between "he" and "llo")
    stream.setStreamCursor(2)

    _ = stream.appendRawKey("X")

    // Expect three raw segments: "he", "X", "llo"; cursor right after X (position 3).
    #expect(stream.segments == [.raw("he"), .raw("X"), .raw("llo")])
    #expect(stream.displayText == "heXllo")
    #expect(stream.streamCursor == 3)
    #expect(stream.activeSegmentIndex == 1)
  }

  // MARK: - Case 2: cursor at boundary of raw segment → freeze (new segment)

  @Test
  func insertRawKey_atRawSegmentBoundary_freezesAndCreatesNewSegment() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendRaw("test")
    // Cursor at left boundary (position 0)
    stream.setStreamCursor(0)

    _ = stream.appendRawKey("X")

    #expect(stream.segments == [.raw("X"), .raw("test")])
    #expect(stream.streamCursor == 1)
    #expect(stream.activeSegmentIndex == 0)
  }

  // MARK: - Case 3: cursor inside chinese segment → split + insert raw

  @Test
  func insertRawKey_insideChineseSegment_splitsAndInsertsNewRaw() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    Self.type("su3cl3", into: &stream)
    #expect(stream.segments == [.chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])])
    // Cursor between 你 and 好 (position 1)
    stream.setStreamCursor(1)

    _ = stream.appendRawKey("X")

    #expect(stream.segments == [
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
      .raw("X"),
      .chinese(text: "好", readings: ["ㄏㄠˇ"]),
    ])
    #expect(stream.displayText == "你X好")
    #expect(stream.streamCursor == 2)
    #expect(stream.activeSegmentIndex == 1)
  }

  // MARK: - Case 4: cursor at TAIL of currently-active raw segment → append

  @Test
  func insertRawKey_atTailOfActiveRawSegment_preservesAppendBehavior() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    _ = stream.appendRawKey("h")
    _ = stream.appendRawKey("e")
    // cursor == 2, active segment is segments[0]=.raw("he"), tail of active.
    #expect(stream.activeSegmentIndex == 0)
    _ = stream.appendRawKey("l")
    #expect(stream.segments == [.raw("hel")])
    #expect(stream.streamCursor == 3)
    #expect(stream.activeSegmentIndex == 0)
  }

  // MARK: - Case 5: zhuyin commit at cursor → applies to NEW active segment

  @Test
  func zhuyinCommit_inMiddleOfStream_appliesToNewActiveSegment() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    Self.type("hello", into: &stream)
    #expect(stream.segments == [.raw("hello")])
    // Move cursor between "hel" and "lo"
    stream.setStreamCursor(3)

    Self.type("su3", into: &stream)

    #expect(stream.segments == [
      .raw("hel"),
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
      .raw("lo"),
    ])
    #expect(stream.displayText == "hel你lo")
    // Cursor right after inserted chinese
    #expect(stream.streamCursor == 4)
  }

  // MARK: - Case 6: backspace auto-merge adjacent same-type segments

  @Test
  func backspaceMergesAdjacentRawSegmentsAfterDeletingMiddle() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    // 構造 [raw("ab"), chinese("你"), raw("cd")]：在中間 chinese 兩側各有 raw。
    stream.appendRaw("ab")
    stream.appendChinese(text: "你", readings: ["ㄋㄧˇ"])
    stream.appendRaw("cd")
    #expect(stream.segments == [
      .raw("ab"),
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
      .raw("cd"),
    ])
    // 把游標移到 chinese 與後 raw 段邊界（unit=3：ab=2 + 你=1）。
    stream.setStreamCursor(3)
    // backspace 應刪掉 "你" 的 reading；隨後相鄰 raw 段自動合併為 raw("abcd")。
    let deletion = stream.backspace(readingCursor: 1)
    #expect(deletion == .chineseReading(text: "你", reading: "ㄋㄧˇ", globalReadingIndex: 0))
    #expect(stream.segments == [.raw("abcd")])
  }

  // MARK: - Cursor movement re-activates raw segment

  @Test
  func movingCursorToTailOfRawSegmentReactivatesIt() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    Self.type("su3", into: &stream)
    stream.appendRaw("ab")
    // segments: [chinese("你"), raw("ab")]; cursor at end (3)
    // Move cursor to start (0) → activeSegmentIndex should be nil
    stream.setStreamCursor(0)
    #expect(stream.activeSegmentIndex == nil)
    // Move cursor to position 3 (tail of raw "ab")
    stream.setStreamCursor(3)
    #expect(stream.activeSegmentIndex == 1)
    #expect(stream.activeRawText == "ab")
  }

  // MARK: - Regression: existing tests must still pass via this path

  // MARK: - backspaceAtStreamCursor coverage (cursor-aware backspace bugfix)

  @Test
  func backspaceAtStreamCursor_atRawTail_deletesLastChar() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendRaw("hello")
    #expect(stream.streamCursor == 5)
    let deletion = stream.backspaceAtStreamCursor()
    #expect(deletion == .rawCharacter("o"))
    #expect(stream.segments == [.raw("hell")])
    #expect(stream.streamCursor == 4)
  }

  @Test
  func backspaceAtStreamCursor_midRaw_deletesCorrectChar() {
    // 回歸測試：舊路徑用 assembler.cursor 作 readingCursor 會在 cursor=3 時
    // 刪錯位置，導致中段 backspace 產出 "hell"。新路徑必須得到 "helo"。
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendRaw("hello")
    stream.setStreamCursor(3)
    let deletion = stream.backspaceAtStreamCursor()
    #expect(deletion == .rawCharacter("l"))
    #expect(stream.segments == [.raw("helo")])
    #expect(stream.streamCursor == 2)
  }

  @Test
  func backspaceAtStreamCursor_atChineseTail_deletesLastReading_andGlobalIndexCorrect() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendChinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])
    #expect(stream.streamCursor == 2)
    let deletion = stream.backspaceAtStreamCursor()
    #expect(deletion == .chineseReading(text: "好", reading: "ㄏㄠˇ", globalReadingIndex: 1))
    #expect(stream.segments == [.chinese(text: "你", readings: ["ㄋㄧˇ"])])
    #expect(stream.streamCursor == 1)
  }

  @Test
  func backspaceAtStreamCursor_atSegmentBoundary_deletesCorrectSide() {
    // Cursor at end of chinese seg (right of "你"): backspace should delete 你 reading.
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendRaw("ab")
    stream.appendChinese(text: "你", readings: ["ㄋㄧˇ"])
    stream.setStreamCursor(3)
    let d1 = stream.backspaceAtStreamCursor()
    #expect(d1 == .chineseReading(text: "你", reading: "ㄋㄧˇ", globalReadingIndex: 0))
    #expect(stream.segments == [.raw("ab")])
    #expect(stream.streamCursor == 2)

    // 另一情境：cursor 落在 raw 與 chinese 邊界 → 刪左側 raw 的最後字元。
    var stream2 = MixedInputSegmentStream(parser: .ofDachen)
    stream2.appendRaw("ab")
    stream2.appendChinese(text: "你", readings: ["ㄋㄧˇ"])
    stream2.setStreamCursor(2)
    let d2 = stream2.backspaceAtStreamCursor()
    #expect(d2 == .rawCharacter("b"))
    #expect(stream2.segments == [.raw("a"), .chinese(text: "你", readings: ["ㄋㄧˇ"])])
    #expect(stream2.streamCursor == 1)
  }

  @Test
  func backspaceAtStreamCursor_removesEmptyActiveSegment_andResetsActiveIndex() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendRaw("a")
    #expect(stream.activeSegmentIndex == 0)
    #expect(stream.streamCursor == 1)
    let deletion = stream.backspaceAtStreamCursor()
    #expect(deletion == .rawCharacter("a"))
    #expect(stream.segments.isEmpty)
    #expect(stream.activeSegmentIndex == nil)
    #expect(stream.streamCursor == 0)
  }

  @Test
  func backspaceAtStreamCursor_triggersMerge_andUpdatesActiveSegmentIndex() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendRaw("ab")
    stream.appendChinese(text: "你", readings: ["ㄋㄧˇ"])
    stream.appendRaw("cd")
    #expect(stream.segments == [
      .raw("ab"),
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
      .raw("cd"),
    ])
    stream.setStreamCursor(3) // 中文段尾
    let deletion = stream.backspaceAtStreamCursor()
    #expect(deletion == .chineseReading(text: "你", reading: "ㄋㄧˇ", globalReadingIndex: 0))
    // 兩側 raw 段被合併（activeSegmentIndex 不可指向已消失的舊 index 2）。
    #expect(stream.segments == [.raw("abcd")])
    #expect(stream.streamCursor == 2)
    if let active = stream.activeSegmentIndex {
      #expect(stream.segments.indices.contains(active))
    }
  }

  @Test
  func backspaceAtStreamCursor_atCursorZero_returnsNil() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendRaw("ab")
    stream.setStreamCursor(0)
    let deletion = stream.backspaceAtStreamCursor()
    #expect(deletion == nil)
    #expect(stream.segments == [.raw("ab")])
  }

  @Test
  func backspaceAtStreamCursor_consecutiveBackspacesToEmpty_doNotCrash() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    for ch in "hello".map(\.description) {
      _ = stream.appendRawKey(ch)
    }
    #expect(stream.streamCursor == 5)
    for _ in 0 ..< 5 {
      _ = stream.backspaceAtStreamCursor()
    }
    #expect(stream.segments.isEmpty)
    #expect(stream.streamCursor == 0)
    // 再做一次保險，確認空 stream 上多按 backspace 不會 crash。
    #expect(stream.backspaceAtStreamCursor() == nil)
  }

  // MARK: - PRIORITY 2 regression: chinese split must drive on readings.count;
  // if text/readings count mismatches, segment must NOT be split.

  @Test
  func insertRawKey_insideChineseSegmentWithMismatchedTextReadings_refusesSplit() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    // Multi-char / single-reading 範例（標點等）：text=「……」，readings=["..."]
    stream.appendChinese(text: "……", readings: ["..."])
    #expect(stream.segments == [.chinese(text: "……", readings: ["..."])])
    // cursor=1 從 displayText 角度落在「……」中間，但 readings.count=1
    // → openNewActiveRawSegmentAtCursor 不應切段，應把新 raw 開在中文段後面。
    stream.setStreamCursor(1)
    _ = stream.appendRawKey("X")
    // chinese 段應保持完整。
    let chineseStillIntact = stream.segments.contains(
      .chinese(text: "……", readings: ["..."])
    )
    #expect(chineseStillIntact)
    // 不應出現切碎的中文段（任一 chinese 段 text 與 readings 字數不一致以外的形變都不允許）。
    for seg in stream.segments {
      if case let .chinese(t, r) = seg {
        #expect(t == "……" && r == ["..."])
      }
    }
  }
}

extension MixedInputSegmentStream_InsertAtCursorTests {
  @Test
  func regression_basicScenarios() {
    let scenarios: [(input: String, expected: [Seg], expectedText: String)] = [
      ("su3cl3", [.chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])], "你好"),
      ("testsu3cl3", [.raw("test"), .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])], "test你好"),
      ("su3cl3test", [.chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]), .raw("test")], "你好test"),
      (
        "su3cl3testsu3cl3",
        [
          .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
          .raw("test"),
          .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
        ],
        "你好test你好"
      ),
      ("Y5.6", [.raw("Y"), .chinese(text: "軸", readings: ["ㄓㄡˊ"])], "Y軸"),
      ("xxul3", [.raw("x"), .chinese(text: "了", readings: ["ㄌㄧㄠˇ"])], "x了"),
    ]
    for sc in scenarios {
      var stream = MixedInputSegmentStream(parser: .ofDachen)
      Self.type(sc.input, into: &stream)
      #expect(stream.segments == sc.expected, "scenario \(sc.input)")
      #expect(stream.displayText == sc.expectedText, "scenario \(sc.input)")
    }
  }
}
