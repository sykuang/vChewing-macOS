import Testing
@testable import Typewriter

@Test func mixedInputPrototypeDetectsObviousBypassScalars() {
  #expect(MixedInputPrototype.shouldBypassDirectly(inputText: "@"))
  #expect(MixedInputPrototype.shouldBypassDirectly(inputText: "/"))
  #expect(MixedInputPrototype.shouldBypassDirectly(inputText: "\\"))
  #expect(!MixedInputPrototype.shouldBypassDirectly(inputText: "a"))
  #expect(!MixedInputPrototype.shouldBypassDirectly(inputText: "1"))
  #expect(!MixedInputPrototype.shouldBypassDirectly(inputText: "."))
}

@Test func mixedInputPrototypeStartsConservativeSequences() {
  #expect(MixedInputPrototype.shouldStartSequence(inputText: "@", hasComposition: false, isPhoneticKey: false))
  #expect(MixedInputPrototype.shouldStartSequence(inputText: "7", hasComposition: false, isPhoneticKey: false))
  #expect(!MixedInputPrototype.shouldStartSequence(inputText: "7", hasComposition: true, isPhoneticKey: false))
  #expect(!MixedInputPrototype.shouldStartSequence(inputText: "/", hasComposition: false, isPhoneticKey: true))
  #expect(!MixedInputPrototype.shouldStartSequence(inputText: "a", hasComposition: false, isPhoneticKey: false))
}

@Test func mixedInputPrototypeContinuesAsciiTokenSequences() {
  #expect(MixedInputPrototype.shouldContinueSequence(inputText: "a"))
  #expect(MixedInputPrototype.shouldContinueSequence(inputText: "Z"))
  #expect(MixedInputPrototype.shouldContinueSequence(inputText: "9"))
  #expect(MixedInputPrototype.shouldContinueSequence(inputText: "."))
  #expect(MixedInputPrototype.shouldContinueSequence(inputText: "-"))
  #expect(!MixedInputPrototype.shouldContinueSequence(inputText: " "))
}
