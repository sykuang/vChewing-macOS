import Foundation
import Shared
import Testing
@testable import Typewriter

extension InputHandlerTests {
  /// Aspiration spec: a complete Zhuyin + English mixed-input flow should allow
  /// valid Zhuyin syllables to compose normally while inline English tokens are
  /// committed without an explicit ASCII-mode switch.
  ///
  /// Example target UX:
  /// - Zhuyin segment: ㄋㄧˇ ㄏㄠˇ -> 你好
  /// - Inline English token: test@example.com
  /// - Zhuyin segment: ㄒㄧㄝˋ ㄒㄧㄝˋ -> 謝謝
  @Test(.disabled("future spec: end-to-end zhuyin+english mixed input not implemented yet"))
  func future_completeZhuyinAndEnglishMixedInputFlow() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }

    clearTestPOM()
    testHandler.prefs.useSCPCTypingMode = false
    testHandler.prefs.keyboardParser = KeyboardParser.ofStandard.rawValue
    testHandler.ensureKeyboardParser()
    testSession.resetInputHandler(forceComposerCleanup: true)

    // Target sentence intent:
    // 「你好 test@example.com 謝謝」
    // Zhuyin (standard layout) should remain valid syllable composition,
    // while the email token should be committed inline as ASCII.

    // NOTE:
    // This is intentionally written as a high-level behavioral expectation.
    // The exact key sequence may evolve as the mixed-input algorithm is refined.
    // The important property is the final mixed-output behavior, not the current
    // implementation detail.

    let expected = "你好 test@example.com 謝謝"

    // Placeholder sequence for future implementation work.
    // When the mixed-input algorithm matures, replace this with a precise key
    // stream that reflects real layout-aware Zhuyin input plus inline English.
    let aspirationalKeyStream = "su3cl3 test@example.com xie4xie4"

    typeSentence(aspirationalKeyStream)
    _ = testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent)

    let committed = testSession.recentCommissions.joined()
    #expect(committed == expected)
  }

  /// Aspiration spec: a complete Hanyu Pinyin + English mixed-input flow should
  /// also be supported under pinyin parser mode.
  @Test(.disabled("future spec: end-to-end pinyin+english mixed input not implemented yet"))
  func future_completePinyinAndEnglishMixedInputFlow() throws {
    guard let testHandler, let testSession else {
      Issue.record("testHandler and testSession at least one of them is nil.")
      return
    }

    clearTestPOM()
    testHandler.prefs.useSCPCTypingMode = false
    testHandler.prefs.keyboardParser = KeyboardParser.ofHanyuPinyin.rawValue
    testHandler.ensureKeyboardParser()
    testSession.resetInputHandler(forceComposerCleanup: true)

    // Target sentence intent:
    // 「你好 macOS14 謝謝」
    // Pinyin syllables should compose legally, and the English token should
    // remain inline without ASCII mode switching.
    let expected = "你好 macOS14 謝謝"

    // Placeholder for future layout-accurate pinyin key stream.
    let aspirationalKeyStream = "ni3hao3 macOS14 xie4xie4"

    typeSentence(aspirationalKeyStream)
    _ = testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent)

    let committed = testSession.recentCommissions.joined()
    #expect(committed == expected)
  }
}
