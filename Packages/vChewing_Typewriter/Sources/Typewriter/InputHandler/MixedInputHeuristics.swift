// (c) 2026 research patch for mixed-input exploration.
// Heuristic overrides and conservative token-shape rules.

import Foundation

public enum MixedInputHeuristics {
  public static func classifyTokenStart(_ context: MixedInputDecisionContext) -> MixedInputTokenKind? {
    guard context.inputText.count == 1, let ch = context.inputText.first else { return nil }

    // High-signal token starts.
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

  public static func canContinueToken(kind: MixedInputTokenKind, with inputText: String) -> Bool {
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
