import Foundation
@testable import Tekkon

struct LegalMixedInputFixture: Sendable {
  let parser: Tekkon.MandarinParser
  let typing: String
  let expectedPhonabet: String
  let label: String
}

enum LegalMixedInputFixtures {
  /// Small seed set only. This is a scaffold for future expansion into a much
  /// larger legality corpus (including the 1300+ toned legal syllables target).
  static let zhuyinStandard: [LegalMixedInputFixture] = [
    .init(parser: .ofDachen, typing: "su3", expectedPhonabet: "ㄋㄧˇ", label: "你"),
    .init(parser: .ofDachen, typing: "cl3", expectedPhonabet: "ㄏㄠˇ", label: "好"),
    .init(parser: .ofDachen, typing: "vu06", expectedPhonabet: "ㄒㄧㄢˊ", label: "嫌"),
  ]

  static let hanyuPinyin: [LegalMixedInputFixture] = [
    .init(parser: .ofHanyuPinyin, typing: "ni3", expectedPhonabet: "ㄋㄧˇ", label: "你"),
    .init(parser: .ofHanyuPinyin, typing: "hao3", expectedPhonabet: "ㄏㄠˇ", label: "好"),
    .init(parser: .ofHanyuPinyin, typing: "xie4", expectedPhonabet: "ㄒㄧㄝˋ", label: "謝"),
  ]
}
