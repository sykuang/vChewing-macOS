import Testing
@testable import Typewriter

@Suite("MixedInputZhuyinBehaviorTests", .serialized)
struct MixedInputZhuyinBehaviorTests {
  /// Spec v1: once a non-phonetic trigger starts a mixed-input token,
  /// common ASCII token characters should continue through the same token.
  @Test func tokenContinuationSupportsEmailLikeShapes() {
    #expect(MixedInputPrototype.shouldBypass(
      inputText: "@",
      hasComposition: false,
      isPhoneticKey: false,
      activeSequence: false,
      isMainAreaNumKey: false
    ))
    #expect(MixedInputPrototype.shouldBypass(
      inputText: "e",
      hasComposition: false,
      isPhoneticKey: false,
      activeSequence: true,
      isMainAreaNumKey: false
    ))
    #expect(MixedInputPrototype.shouldBypass(
      inputText: ".",
      hasComposition: false,
      isPhoneticKey: false,
      activeSequence: true,
      isMainAreaNumKey: false
    ))
  }

  /// Spec v1: top-row digits must NOT start mixed-input on their own in
  /// Zhuyin mode, because those keys are commonly mapped to phonetic input.
  @Test func topRowDigitsDoNotStartMixedInputInZhuyinMode() {
    #expect(!MixedInputPrototype.shouldBypass(
      inputText: "1",
      hasComposition: false,
      isPhoneticKey: true,
      activeSequence: false,
      isMainAreaNumKey: true
    ))
    #expect(!MixedInputPrototype.shouldBypass(
      inputText: "7",
      hasComposition: false,
      isPhoneticKey: false,
      activeSequence: false,
      isMainAreaNumKey: true
    ))
  }

  /// Spec v1: once a token has already started from a safe trigger,
  /// top-row digits may continue the token (for version strings, emails,
  /// filenames, etc.).
  @Test func topRowDigitsMayContinueMixedInputToken() {
    #expect(MixedInputPrototype.shouldBypass(
      inputText: "4",
      hasComposition: false,
      isPhoneticKey: false,
      activeSequence: true,
      isMainAreaNumKey: true
    ))
  }

  /// Spec v1: if a key is valid for the phonetic composer, mixed-input must
  /// not steal it, even if it looks ASCII.
  @Test func validPhoneticKeysMustWinOverMixedInput() {
    #expect(!MixedInputPrototype.shouldBypass(
      inputText: "/",
      hasComposition: false,
      isPhoneticKey: true,
      activeSequence: false,
      isMainAreaNumKey: false
    ))
    #expect(!MixedInputPrototype.shouldBypass(
      inputText: "a",
      hasComposition: false,
      isPhoneticKey: true,
      activeSequence: false,
      isMainAreaNumKey: false
    ))
  }

  /// Spec v1: token sequences should stop on whitespace.
  @Test func whitespaceDoesNotContinueMixedInputToken() {
    #expect(!MixedInputPrototype.shouldBypass(
      inputText: " ",
      hasComposition: false,
      isPhoneticKey: false,
      activeSequence: true,
      isMainAreaNumKey: false
    ))
  }

  /// Spec v1 aspirational case: plain English words should eventually be able
  /// to start mixed-input directly in Zhuyin mode without a manual ASCII mode
  /// switch. This is not implemented yet, but the desired behavior is encoded
  /// here as a future target.
  @Test(.disabled("future spec: plain English token auto-start not implemented yet"))
  func future_plainEnglishWordsCanStartMixedInput() {
    #expect(MixedInputPrototype.shouldBypass(
      inputText: "t",
      hasComposition: false,
      isPhoneticKey: false,
      activeSequence: false,
      isMainAreaNumKey: false
    ))
  }
}
