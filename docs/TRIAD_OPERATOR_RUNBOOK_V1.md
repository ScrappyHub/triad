# TRIAD Operator Runbook v1

## What TRIAD is

TRIAD is a standalone deterministic instrument for:

- capture and restore
- native archive pack, verify, and extract
- deterministic transform apply and verify
- non-mutating verification with reproducible proof output

TRIAD is designed to prove exactly what it did and to fail explicitly when invariants are violated.

## Environment Contract

- Windows PowerShell 5.1
- `Set-StrictMode -Version Latest`
- UTF-8 no BOM
- LF line endings
- write -> parse-gate -> child execution
- no interactive-state dependency
- no network dependency for core proof lane

## Full-Green Command

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\scripts\_RUN_triad_full_green_v1.ps1 `
  -RepoRoot .
```

## Expected Success Token

```text
TRIAD_TIER0_FULL_GREEN
```

## Proof Output

```text
proofs\freeze\triad_tier0_<timestamp>\
  full_green_transcript.txt
  sha256sums.txt
  triad.freeze.receipt.json
```

## What Full Green Means

Full green means all authoritative TRIAD proof lanes passed deterministically.

## Operator Guidance

- run TRIAD from a clean working state when producing formal proof output
- preserve freeze outputs immutably once generated
- treat transcript, sha256sums, and freeze receipt as authoritative proof artifacts
- do not modify proof bundles after generation
