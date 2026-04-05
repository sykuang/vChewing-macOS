# vChewing Mixed Input Handoff Status

## Repo / branch

- Upstream: `https://github.com/vChewing/vChewing-macOS`
- Fork: `https://github.com/sykuang/vChewing-macOS`
- Local repo: `research/vChewing-macOS`
- Active branch: `mixed-input-research`

## Goal

Investigate whether vChewing can support ASUS Smart Input–style mixed Chinese/English input for Zhuyin (and later pinyin) without explicit ASCII-mode switching.

## Current conclusion

This is feasible only if mixed-input decision making is gated by phonetic legality / validity.
Raw ASCII-trigger heuristics alone are not sufficient, because many ASCII keys are legitimate bopomofo keys under existing layouts.

## What has been done

### 1. Mixed-input prototype hook exists
Current hook lives in:
- `Packages/vChewing_Typewriter/Sources/Typewriter/InputHandler/InputHandler_MixedInputPrototype.swift`
- integrated from `InputHandler_TriageInput.swift`

Current behavior is still prototype-level and conservative.

### 2. Decider extracted and refactored
Files:
- `Packages/vChewing_Typewriter/Sources/Typewriter/InputHandler/MixedInputCoreDecider.swift`
- `Packages/vChewing_Typewriter/Sources/Typewriter/InputHandler/MixedInputHeuristics.swift`
- `Packages/vChewing_Typewriter/Sources/Typewriter/InputHandler/MixedInputDecider.swift`
- `DevLab/MixedInputDecider.md`

Architecture now is:
- Core decider = main algorithm skeleton
- Heuristics = token-shape / high-signal overrides
- Facade = stable single entry point

### 3. Tests added
#### Mixed-input related tests
- `MixedInputPrototypeTests.swift`
- `MixedInputZhuyinBehaviorTests.swift`
- `MixedInputDeciderTests.swift`
- `MixedInputCompleteFlowTests.swift`

#### Legal fixture validation
- `Fixtures/LegalMixedInputFixtures.swift`
- `LegalMixedInputFixtureTests.swift`

### 4. Existing regression coverage preserved
`swift test` currently passes in `Packages/vChewing_Typewriter`.
At the moment of writing, the test suite is green with:
- 48 tests
- 5 suites

## Important lessons already learned

### A. Wrong approach (already tested)
Do **not** start mixed-input directly from raw ASCII heuristics in the event-routing layer.
This broke baseline behavior because keys like `/` can be valid Zhuyin keys depending on layout/composer state.

### B. Better approach
Use phonetic-validity-first decision making:
1. ask whether the incoming key / sequence is still a valid phonetic continuation
2. if yes, prefer Zhuyin/pinyin
3. if no, only then enter ASCII/token classification

### C. Heuristics should only be supplements
Heuristics should remain a small override layer for high-signal cases such as:
- `@` -> email-like
- `/`, `~`, `\\` -> path-like
- `:`, `#` -> url-like

They should not be the main decision engine.

## Current limitations

### Not implemented yet
- real `ZhuyinSyllableLegality` engine (`invalid` / `prefixValid` / `complete` / `completeWithTone`)
- equivalent legality engine for pinyin
- decider integration with legality engine (currently only boolean-like phonetic validity is used)
- full plain-English auto-start (`test`, `AAPL`, `macOS`) in Zhuyin mode
- complete end-to-end mixed-input flow implementation

### Current complete-flow tests are aspirational specs only
In `MixedInputCompleteFlowTests.swift`, the following tests are intentionally disabled:
- `future_completeZhuyinAndEnglishMixedInputFlow`
- `future_completePinyinAndEnglishMixedInputFlow`

They encode target behavior but are not implemented yet.

## Why legal fixtures were introduced
We found that fake-looking or guessed key sequences can easily pollute mixed-input testing.
A fixture validator already caught one bad Zhuyin sample and forced correction.

That means future work should continue to:
- validate all syllable fixtures against Tekkon/composer behavior first
- only then use them in mixed-input flow tests

## Recommended next step for coding agent

### Priority 1: Implement `ZhuyinSyllableLegality`
Suggested output states:
- `invalid`
- `prefixValid`
- `complete`
- `completeWithTone`

Suggested implementation strategies:
1. either wrap existing Tekkon/composer structure if enough state is already exposed
2. or build a legality helper from validated legal syllable fixtures / trie-like state

### Priority 2: Prepare decider to consume legality state
Replace current boolean-like phonetic gate with richer legality input.
Core decision logic should start using:
- invalid => token classifier may start
- prefixValid => prefer Zhuyin
- complete / completeWithTone => prefer phonetic path until boundary or commit logic says otherwise

### Priority 3: Expand legal syllable fixture corpus
Current fixture set is only a seed set, not a full corpus.
Expand toward:
- more legal toned Zhuyin syllables
- more legal toned Hanyu Pinyin syllables
- eventually broader coverage approaching the hundreds / 1300+ toned legal syllables target

## Suggested guardrails for the coding agent

- Do not remove existing passing regression tests.
- Do not replace legal fixtures with guessed sequences without validator coverage.
- Keep heuristics separate from core decision logic.
- Prefer adding legality tests before widening mixed-input behavior.
- Maintain `swift test` green in `Packages/vChewing_Typewriter` after each step.

## Useful local commands

Run tests:
```bash
cd research/vChewing-macOS/Packages/vChewing_Typewriter
swift test
```

Check branch:
```bash
cd research/vChewing-macOS
git status --short --branch
```

## Latest state summary

The repo is in a good handoff state:
- research branch exists and is pushed
- decider architecture is split into core + heuristics
- tests are green
- legal fixture validation exists
- next real milestone is legality-engine implementation
