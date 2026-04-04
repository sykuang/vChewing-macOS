// (c) 2026 research patch for mixed-input exploration.
// Core mixed-input decision engine for Zhuyin mixed input.

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

public struct MixedInputCoreDecider: Sendable {
  public init() {}

  public func decide(
    _ context: MixedInputDecisionContext,
    classifyTokenStart: (MixedInputDecisionContext) -> MixedInputTokenKind?,
    canContinueToken: (MixedInputTokenKind, String) -> Bool
  ) -> MixedInputDecision {
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
      return canContinueToken(kind, context.inputText) ? .continueToken(kind) : .endToken
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
}

extension MixedInputTokenState {
  var isActive: Bool {
    if case .active = self { return true }
    return false
  }
}
