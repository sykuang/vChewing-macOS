// (c) 2026 research patch for mixed-input exploration.
// This module extracts mixed-input decision making into a standalone,
// testable component so that heuristics are not scattered across the IME
// event-routing layer.

import Foundation

public enum MixedInputTokenKind: Equatable, Sendable {
  case asciiWord
  case numeric
  case urlLike
  case emailLike
  case pathLike
  case unknown
}

public enum MixedInputTokenState: Equatable, Sendable {
  case inactive
  case active(kind: MixedInputTokenKind, buffer: String)
}

public struct MixedInputDecisionContext: Equatable, Sendable {
  public var inputText: String
  public var hasComposition: Bool
  public var isPhoneticKey: Bool
  public var isMainAreaNumKey: Bool
  public var isASCII: Bool
  public var isPrintableASCII: Bool
  public var tokenState: MixedInputTokenState

  public init(
    inputText: String,
    hasComposition: Bool,
    isPhoneticKey: Bool,
    isMainAreaNumKey: Bool,
    isASCII: Bool,
    isPrintableASCII: Bool,
    tokenState: MixedInputTokenState
  ) {
    self.inputText = inputText
    self.hasComposition = hasComposition
    self.isPhoneticKey = isPhoneticKey
    self.isMainAreaNumKey = isMainAreaNumKey
    self.isASCII = isASCII
    self.isPrintableASCII = isPrintableASCII
    self.tokenState = tokenState
  }
}

public enum MixedInputDecision: Equatable, Sendable {
  case continueZhuyin
  case startToken(MixedInputTokenKind)
  case continueToken(MixedInputTokenKind)
  case endToken
  case noDecision
}

public struct MixedInputDecider: Sendable {
  public init() {}

  public func decide(_ context: MixedInputDecisionContext) -> MixedInputDecision {
    guard context.isASCII, context.isPrintableASCII else {
      return context.tokenState.isActive ? .endToken : .noDecision
    }

    if context.isPhoneticKey {
      return context.tokenState.isActive ? .endToken : .continueZhuyin
    }

    switch context.tokenState {
    case .inactive:
      guard let kind = classifyTokenStart(context) else { return .noDecision }
      return .startToken(kind)
    case let .active(kind, _):
      return canContinueToken(kind: kind, with: context.inputText) ? .continueToken(kind) : .endToken
    }
  }

  public func transition(
    from state: MixedInputTokenState,
    with decision: MixedInputDecision,
    inputText: String
  ) -> MixedInputTokenState {
    switch decision {
    case let .startToken(kind):
      return .active(kind: kind, buffer: inputText)
    case let .continueToken(kind):
      switch state {
      case let .active(_, buffer): return .active(kind: kind, buffer: buffer + inputText)
      case .inactive: return .active(kind: kind, buffer: inputText)
      }
    case .endToken, .continueZhuyin, .noDecision:
      return .inactive
    }
  }

  private func classifyTokenStart(_ context: MixedInputDecisionContext) -> MixedInputTokenKind? {
    guard context.inputText.count == 1, let ch = context.inputText.first else { return nil }

    if ["@"].contains(ch) { return .emailLike }
    if ["/", "~", "\\"].contains(ch) { return .pathLike }
    if [":", "#"].contains(ch) { return .urlLike }

    // Keep top-row digits conservative in Zhuyin mode.
    if context.isMainAreaNumKey { return nil }
    if !context.hasComposition, ch.isNumber { return .numeric }

    // Future expansion target: plain ASCII words may start here later, but are
    // intentionally disabled for now because they are the hardest part to
    // disambiguate against Zhuyin keyboard layouts.
    return nil
  }

  private func canContinueToken(kind: MixedInputTokenKind, with inputText: String) -> Bool {
    guard inputText.count == 1, let ch = inputText.first else { return false }
    switch kind {
    case .asciiWord:
      return ch.isLetter || ch.isNumber || ["_", "-"].contains(ch)
    case .numeric:
      return ch.isNumber || [".", ",", "-", "+"].contains(ch)
    case .urlLike:
      return ch.isLetter || ch.isNumber || [":", "/", ".", "?", "&", "=", "#", "_", "-", "%"].contains(ch)
    case .emailLike:
      return ch.isLetter || ch.isNumber || ["@", ".", "_", "-", "+"].contains(ch)
    case .pathLike:
      return ch.isLetter || ch.isNumber || ["/", "\\", "~", ".", "_", "-"].contains(ch)
    case .unknown:
      return false
    }
  }
}

private extension MixedInputTokenState {
  var isActive: Bool {
    if case .active = self { return true }
    return false
  }
}
