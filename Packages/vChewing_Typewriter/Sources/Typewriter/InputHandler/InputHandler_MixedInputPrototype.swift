// (c) 2026 research patch for mixed-input exploration.
// This file introduces a minimal, low-risk mixed-input prototype layer.
// It intentionally handles only obvious ASCII bypass cases so that the
// upstream phonetic composition pipeline remains mostly untouched.

import Foundation

@MainActor
private enum MixedInputPrototypeTracker {
  static var activeSessionIDs: Set<UUID> = []

  static func activate(sessionID: UUID) {
    activeSessionIDs.insert(sessionID)
  }

  static func deactivate(sessionID: UUID) {
    activeSessionIDs.remove(sessionID)
  }

  static func isActive(sessionID: UUID) -> Bool {
    activeSessionIDs.contains(sessionID)
  }
}

struct MixedInputPrototype {
  /// Strong triggers that usually indicate URL / email / path / command-like
  /// inline ASCII text. These can safely start a passthrough streak *only*
  /// when the current typing method does not consider them valid phonetic keys.
  static let obviousBypassScalars: Set<Character> = ["@", "/", "\\", "~", "#", ":"]

  /// Allowed continuation characters once a passthrough streak has started.
  static let continuationScalars: Set<Character> = [
    "@", "/", "\\", "~", "#", ":", ".", "_", "-", "+", "=", "?", "&", "%"
  ]

  static func shouldBypassDirectly(inputText: String) -> Bool {
    guard inputText.count == 1, let char = inputText.first else { return false }
    return obviousBypassScalars.contains(char)
  }

  static func shouldStartSequence(
    inputText: String,
    hasComposition: Bool,
    isPhoneticKey: Bool
  ) -> Bool {
    guard inputText.count == 1, let char = inputText.first else { return false }
    guard !isPhoneticKey else { return false }
    if obviousBypassScalars.contains(char) { return true }
    if !hasComposition, char.isNumber { return true }
    return false
  }

  static func shouldContinueSequence(inputText: String) -> Bool {
    guard inputText.count == 1, let char = inputText.first else { return false }
    if char.isLetter || char.isNumber { return true }
    return continuationScalars.contains(char)
  }
}

extension InputHandlerProtocol {
  /// Experimental mixed-input prototype.
  ///
  /// Design goal:
  /// - keep existing explicit ASCII mode untouched
  /// - avoid interfering with normal Zhuyin/Pinyin key processing
  /// - only bypass for conservative token-like ASCII sequences
  /// - never steal a key that the current phonetic composer already accepts
  ///
  /// v3 behavior:
  /// - a sequence can start only if the incoming ASCII key is NOT a valid
  ///   phonetic key for the current composer/layout
  /// - once started, continuation characters may pass through until a
  ///   non-token character arrives
  func handleMixedInputPrototype(input: InputSignalProtocol) -> Bool {
    guard let session = session else { return false }
    let sessionID = session.id
    defer {
      if !(input.isASCII && input.charCode.isPrintableASCII) {
        MixedInputPrototypeTracker.deactivate(sessionID: sessionID)
      }
    }

    guard !session.isASCIIMode else {
      MixedInputPrototypeTracker.deactivate(sessionID: sessionID)
      return false
    }
    guard input.isASCII, input.charCode.isPrintableASCII else { return false }
    guard !input.isCommandHold, !input.isControlHold, !input.isOptionHold else {
      MixedInputPrototypeTracker.deactivate(sessionID: sessionID)
      return false
    }
    guard !input.isCapsLockOn else {
      MixedInputPrototypeTracker.deactivate(sessionID: sessionID)
      return false
    }
    guard !input.isTab, !input.isBackSpace, !input.isDelete, !input.isEsc else {
      MixedInputPrototypeTracker.deactivate(sessionID: sessionID)
      return false
    }
    guard !input.isEnter, !input.isPageUp, !input.isPageDown else {
      MixedInputPrototypeTracker.deactivate(sessionID: sessionID)
      return false
    }
    guard !input.isLeft, !input.isRight, !input.isUp, !input.isDown else {
      MixedInputPrototypeTracker.deactivate(sessionID: sessionID)
      return false
    }
    guard !input.isNumericPadKey, !input.isMainAreaNumKey else { return false }

    let normalizedText = (input.inputTextIgnoringModifiers ?? input.text)
      .lowercased()
      .applyingTransformFW2HW(reverse: false)
    let isPhoneticKey = composer.inputValidityCheck(charStr: normalizedText)
    let active = MixedInputPrototypeTracker.isActive(sessionID: sessionID)
    let shouldBypass = MixedInputPrototype.shouldStartSequence(
      inputText: input.text,
      hasComposition: session.state.hasComposition,
      isPhoneticKey: isPhoneticKey
    ) || (active && MixedInputPrototype.shouldContinueSequence(inputText: input.text))

    guard shouldBypass else {
      MixedInputPrototypeTracker.deactivate(sessionID: sessionID)
      return false
    }

    MixedInputPrototypeTracker.activate(sessionID: sessionID)
    let prefix = session.state.hasComposition
      ? generateStateOfInputting(sansReading: true).displayedText
      : ""
    session.switchState(State.ofCommitting(textToCommit: prefix + input.text))
    return true
  }
}
