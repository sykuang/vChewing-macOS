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
              acceptsLeadingIntonation: true,
              requiresWordLikeRawPrefix: false
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
}
