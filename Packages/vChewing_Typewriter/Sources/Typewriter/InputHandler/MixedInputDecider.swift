// (c) 2026 research patch for mixed-input exploration.
// Facade that combines the core decider with heuristic overrides.

import Foundation

public struct MixedInputDecider: Sendable {
  private let core = MixedInputCoreDecider()

  public init() {}

  public func decide(_ context: MixedInputDecisionContext) -> MixedInputDecision {
    core.decide(
      context,
      classifyTokenStart: MixedInputHeuristics.classifyTokenStart,
      canContinueToken: MixedInputHeuristics.canContinueToken(kind:with:)
    )
  }

  public func transition(
    from state: MixedInputTokenState,
    with decision: MixedInputDecision,
    inputText: String
  ) -> MixedInputTokenState {
    core.transition(from: state, with: decision, inputText: inputText)
  }
}
