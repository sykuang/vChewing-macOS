// (c) 2026 research patch for mixed-input exploration.
// This file introduces a minimal, low-risk mixed-input prototype layer.
// It intentionally handles only obvious ASCII bypass cases so that the
// upstream phonetic composition pipeline remains mostly untouched.

import Foundation

struct MixedInputPrototype {
  /// A conservative list of ASCII characters that are strong signals for
  /// inline English / path / URL / email-like input and are unlikely to be
  /// intended as regular phonetic continuation.
  static let obviousBypassScalars: Set<Character> = ["@", "/", "\\", "~", "#", ":"]

  static func shouldBypassDirectly(inputText: String) -> Bool {
    guard inputText.count == 1, let char = inputText.first else { return false }
    return obviousBypassScalars.contains(char)
  }
}

extension InputHandlerProtocol {
  /// Experimental mixed-input prototype.
  ///
  /// Design goal:
  /// - keep existing explicit ASCII mode untouched
  /// - avoid interfering with normal Zhuyin/Pinyin key processing
  /// - only bypass for obvious ASCII symbols that strongly suggest
  ///   email / URL / path / command-like input
  ///
  /// This is deliberately conservative. It acts as a scaffolding point for
  /// future token-level mixed-input classification.
  func handleMixedInputPrototype(input: InputSignalProtocol) -> Bool {
    guard let session = session else { return false }
    guard !session.isASCIIMode else { return false }
    guard input.isASCII, input.charCode.isPrintableASCII else { return false }
    guard !input.isCommandHold, !input.isControlHold, !input.isOptionHold else { return false }
    guard !input.isCapsLockOn else { return false }
    guard !input.isTab, !input.isBackSpace, !input.isDelete, !input.isEsc else { return false }
    guard !input.isEnter, !input.isPageUp, !input.isPageDown else { return false }
    guard !input.isLeft, !input.isRight, !input.isUp, !input.isDown else { return false }
    guard !input.isNumericPadKey, !input.isMainAreaNumKey else { return false }
    guard MixedInputPrototype.shouldBypassDirectly(inputText: input.text) else { return false }

    let prefix = session.state.hasComposition
      ? generateStateOfInputting(sansReading: true).displayedText
      : ""
    session.switchState(State.ofCommitting(textToCommit: prefix + input.text))
    return true
  }
}
