import Testing
@testable import Typewriter

@Suite("MixedInputDeciderTests", .serialized)
struct MixedInputDeciderTests {
  let decider = MixedInputDecider()

  @Test func phoneticKeyWinsOverMixedInput() {
    let context = MixedInputDecisionContext(
      inputText: "/",
      hasComposition: false,
      isPhoneticKey: true,
      isMainAreaNumKey: false,
      isASCII: true,
      isPrintableASCII: true,
      tokenState: .inactive
    )
    #expect(decider.decide(context) == .continueZhuyin)
  }

  @Test func nonPhoneticAtStartsEmailLikeToken() {
    let context = MixedInputDecisionContext(
      inputText: "@",
      hasComposition: false,
      isPhoneticKey: false,
      isMainAreaNumKey: false,
      isASCII: true,
      isPrintableASCII: true,
      tokenState: .inactive
    )
    #expect(decider.decide(context) == .startToken(.emailLike))
  }

  @Test func activeEmailTokenContinuesWithLettersAndDots() {
    let active = MixedInputTokenState.active(kind: .emailLike, buffer: "@exam")
    let dotContext = MixedInputDecisionContext(
      inputText: ".",
      hasComposition: false,
      isPhoneticKey: false,
      isMainAreaNumKey: false,
      isASCII: true,
      isPrintableASCII: true,
      tokenState: active
    )
    #expect(decider.decide(dotContext) == .continueToken(.emailLike))
  }

  @Test func activeTokenEndsWhenPhoneticKeyTakesOver() {
    let active = MixedInputTokenState.active(kind: .pathLike, buffer: "~/dev")
    let context = MixedInputDecisionContext(
      inputText: "/",
      hasComposition: false,
      isPhoneticKey: true,
      isMainAreaNumKey: false,
      isASCII: true,
      isPrintableASCII: true,
      tokenState: active
    )
    #expect(decider.decide(context) == .endToken)
  }

  @Test func topRowDigitDoesNotStartTokenByItself() {
    let context = MixedInputDecisionContext(
      inputText: "1",
      hasComposition: false,
      isPhoneticKey: false,
      isMainAreaNumKey: true,
      isASCII: true,
      isPrintableASCII: true,
      tokenState: .inactive
    )
    #expect(decider.decide(context) == .noDecision)
  }

  @Test func topRowDigitCanContinueNumericToken() {
    let active = MixedInputTokenState.active(kind: .numeric, buffer: "12")
    let context = MixedInputDecisionContext(
      inputText: "3",
      hasComposition: false,
      isPhoneticKey: false,
      isMainAreaNumKey: true,
      isASCII: true,
      isPrintableASCII: true,
      tokenState: active
    )
    #expect(decider.decide(context) == .continueToken(.numeric))
  }
}
