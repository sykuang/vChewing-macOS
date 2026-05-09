import Tekkon
import Testing
@testable import Typewriter

@Suite("MixedInputSegmentStreamTests", .serialized)
struct MixedInputSegmentStreamTests {
  struct Scenario: Sendable {
    let input: String
    let conversions: [String: (text: String, readings: [String])]
    let expectedSegments: [MixedInputSegmentStream.Segment]
    let expectedDisplayText: String
  }

  @Test(arguments: [
    Scenario(
      input: "su3cl3",
      conversions: ["su3": ("你", ["ㄋㄧˇ"]), "cl3": ("好", ["ㄏㄠˇ"])],
      expectedSegments: [.chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])],
      expectedDisplayText: "你好"
    ),
    Scenario(
      input: "testsu3cl3",
      conversions: ["su3": ("你", ["ㄋㄧˇ"]), "cl3": ("好", ["ㄏㄠˇ"])],
      expectedSegments: [.raw("test"), .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])],
      expectedDisplayText: "test你好"
    ),
    Scenario(
      input: "su3cl3test",
      conversions: ["su3": ("你", ["ㄋㄧˇ"]), "cl3": ("好", ["ㄏㄠˇ"])],
      expectedSegments: [.chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]), .raw("test")],
      expectedDisplayText: "你好test"
    ),
    Scenario(
      input: "su3cl3testsu3cl3",
      conversions: ["su3": ("你", ["ㄋㄧˇ"]), "cl3": ("好", ["ㄏㄠˇ"])],
      expectedSegments: [
        .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
        .raw("test"),
        .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      ],
      expectedDisplayText: "你好test你好"
    ),
    Scenario(
      input: "Y5.6",
      conversions: ["5.6": ("軸", ["ㄓㄡˊ"])],
      expectedSegments: [.raw("Y"), .chinese(text: "軸", readings: ["ㄓㄡˊ"])],
      expectedDisplayText: "Y軸"
    ),
    Scenario(
      input: "xxul3",
      conversions: ["xul3": ("了", ["ㄌㄧㄠˇ"])],
      expectedSegments: [.raw("x"), .chinese(text: "了", readings: ["ㄌㄧㄠˇ"])],
      expectedDisplayText: "x了"
    ),
  ])
  func arbitraryInputIsRepresentedAsTrieRawSegmentStream(_ scenario: Scenario) {
    var stream = MixedInputSegmentStream(parser: .ofDachen)

    for key in scenario.input.map(\.description) {
      let commit = stream.appendRawKey(key)
      guard let commit, let conversion = scenario.conversions[commit.suffix],
            let replacement = stream.chineseReplacement(
              for: commit,
              chineseText: conversion.text,
              readings: conversion.readings,
              acceptsLeadingIntonation: true
            )
      else {
        continue
      }
      stream.replaceActiveRawWithChinese(replacement)
    }

    #expect(stream.segments == scenario.expectedSegments)
    #expect(stream.displayText == scenario.expectedDisplayText)
    #expect(stream.displayTextSegments.joined() == scenario.expectedDisplayText)
  }

  @Test
  func displayCursorMovesToTailWhenReadingCursorIsAtEndWithActiveRawTail() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendChinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])
    stream.appendRaw("test")

    #expect(stream.displayText == "你好test")
    #expect(stream.readingCount == 2)
    #expect(stream.displayCursor(forReadingCursor: 2) == "你好test".count)
    #expect(stream.displayCursor(forReadingCursor: 1) == 1)
    #expect(stream.displayCursor(forReadingCursor: 0) == 0)
  }

  @Test
  func backspaceRemovingRawTailThenChineseCommitMergesAdjacentChineseSegments() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    let conversions: [String: (text: String, readings: [String])] = [
      "su3": ("你", ["ㄋㄧˇ"]),
      "cl3": ("好", ["ㄏㄠˇ"]),
    ]

    func type(_ input: String) {
      for key in input.map(\.description) {
        let commit = stream.appendRawKey(key)
        guard let commit, let conversion = conversions[commit.suffix],
              let replacement = stream.chineseReplacement(
                for: commit,
                chineseText: conversion.text,
                readings: conversion.readings,
                acceptsLeadingIntonation: true
              )
        else {
          continue
        }
        stream.replaceActiveRawWithChinese(replacement)
      }
    }

    type("su3cl3test")
    #expect(stream.segments == [
      .chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"]),
      .raw("test"),
    ])

    for removed in ["t", "s", "e", "t"] {
      let deletion = stream.backspace()
      #expect(deletion == .rawCharacter(removed))
    }
    #expect(stream.segments == [.chinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])])

    type("cl3")
    #expect(stream.segments == [.chinese(text: "你好好", readings: ["ㄋㄧˇ", "ㄏㄠˇ", "ㄏㄠˇ"])])
    #expect(stream.displayText == "你好好")
    #expect(stream.displayTextSegments == ["你好好"])
    #expect(stream.activeRawText.isEmpty)
  }

  @Test
  func backspaceReturnsExplicitDeletionResultsForRawAndChineseSegments() {
    var stream = MixedInputSegmentStream(parser: .ofDachen)
    stream.appendRaw(" ")
    stream.appendChinese(text: "你好", readings: ["ㄋㄧˇ", "ㄏㄠˇ"])

    let deleteHao = stream.backspace(readingCursor: 2)
    #expect(deleteHao == .chineseReading(text: "好", reading: "ㄏㄠˇ", globalReadingIndex: 1))
    #expect(stream.segments == [
      .raw(" "),
      .chinese(text: "你", readings: ["ㄋㄧˇ"]),
    ])
    #expect(stream.displayText == " 你")

    let deleteNi = stream.backspace(readingCursor: 1)
    #expect(deleteNi == .chineseReading(text: "你", reading: "ㄋㄧˇ", globalReadingIndex: 0))
    #expect(stream.segments == [.raw(" ")])

    let deleteSpace = stream.backspace()
    #expect(deleteSpace == .rawCharacter(" "))
    #expect(stream.segments.isEmpty)
  }
}
