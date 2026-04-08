# TRIAD

TRIAD is a standalone deterministic instrument for capture, restore, archive, transform, and verification workflows.

TRIAD does not require external archive tools or external services for its core proof lane. It proves itself locally through deterministic selftests, adversarial negatives, stress coverage, and a single full-green runner.

## Environment

- Windows PowerShell 5.1
- `Set-StrictMode -Version Latest`
- UTF-8 no BOM
- LF line endings
- write -> parse-gate -> child execution
- no interactive-state dependency
- no network dependency for core proof

## One Command

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\scripts\_RUN_triad_full_green_v1.ps1 `
  -RepoRoot .
```

## Expected Output

```text
TRIAD_TIER0_FULL_GREEN
```

## Output Artifacts

```text
proofs\freeze\triad_tier0_<timestamp>\
  full_green_transcript.txt
  sha256sums.txt
  triad.freeze.receipt.json
```

## Docs

- `docs\TRIAD_OPERATOR_RUNBOOK_V1.md`
- `docs\TRIAD_PROOF_MAP_V1.md`
- `docs\TRIAD_EXTERNAL_VERIFICATION_V1.md`
- `docs\TRIAD_RELEASE_STRUCTURE_V1.md`

## Operator Rule

Do not trust TRIAD output by default. Verify using the produced transcript, hashes, and freeze receipt.
