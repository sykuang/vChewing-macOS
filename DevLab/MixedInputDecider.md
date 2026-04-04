# MixedInputDecider (research design note)

## Goal

Provide a layout-aware, phonetic-validity-first decision core for Zhuyin mixed input.

## Core principle

1. Ask the phonetic composer first whether the incoming key is a valid Zhuyin continuation.
2. If valid, prefer Zhuyin.
3. If invalid, enter ASCII/token classification.

This avoids the major failure mode discovered during earlier prototype patches:
stealing keys that are legitimate bopomofo keys in the current layout.

## Decision layers

### 1. Phonetic validity gate
Input:
- current composer state
- normalized input text
- current layout/typing method

Output:
- `isPhoneticKey: Bool`

### 2. Token classifier
Possible token kinds:
- `asciiWord`
- `numeric`
- `urlLike`
- `emailLike`
- `pathLike`
- `unknown`

### 3. Token FSM
States:
- `inactive`
- `active(kind:buffer:)`

Decisions:
- `continueZhuyin`
- `startToken(kind)`
- `continueToken(kind)`
- `endToken`
- `noDecision`

## Conservative v1 strategy

- phonetic-valid keys always win
- `@` starts `emailLike`
- `/`, `~`, `\\` start `pathLike`
- `:`, `#` start `urlLike`
- top-row digits do not start tokens by themselves in Zhuyin mode
- active tokens may continue with token-specific continuation characters

## Future expansion targets

- plain English word auto-start (`test`, `AAPL`, `macOS`)
- sentence-level Chinese/English boundary detection
- scoring model instead of purely deterministic starts
- separate handling for version strings
