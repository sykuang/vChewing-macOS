import Foundation
import Shared
import Testing
@testable import Tekkon
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

    let zhuyinFixtures = LegalMixedInputFixtures.zhuyinStandard
    #expect(zhuyinFixtures.count >= 3)

    // Validate fixture legality up-front so this aspiration spec never drifts
    // onto fake or malformed test data.
    for fixture in zhuyinFixtures {
      var composer = Tekkon.Composer(arrange: fixture.parser)
      #expect(composer.receiveSequence(fixture.typing) == fixture.expectedPhonabet)
    }

    // Placeholder sequence for future implementation work.
    // This is now assembled from validated legal syllable fixtures plus an
    // inline English token.
    let aspirationalKeyStream = zhuyinFixtures[0].typing + zhuyinFixtures[1].typing + " test@example.com " + zhuyinFixtures[2].typing + zhuyinFixtures[2].typing

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

    let pinyinFixtures = LegalMixedInputFixtures.hanyuPinyin
    #expect(pinyinFixtures.count >= 3)

    // Validate fixture legality up-front so this aspiration spec uses real,
    // parser-accepted pinyin syllables.
    for fixture in pinyinFixtures {
      var composer = Tekkon.Composer(arrange: fixture.parser)
      #expect(composer.receiveSequence(fixture.typing) == fixture.expectedPhonabet)
    }

    // Placeholder for future layout-accurate pinyin key stream, assembled from
    // validated fixtures.
    let aspirationalKeyStream = pinyinFixtures[0].typing + pinyinFixtures[1].typing + " macOS14 " + pinyinFixtures[2].typing + pinyinFixtures[2].typing

    typeSentence(aspirationalKeyStream)
    _ = testHandler.triageInput(event: KBEvent.KeyEventData.dataEnterReturn.asEvent)

    let committed = testSession.recentCommissions.joined()
    #expect(committed == expected)
  }
}
