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
