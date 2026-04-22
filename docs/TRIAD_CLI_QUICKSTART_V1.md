# TRIAD CLI Quickstart v1

## Open the repo root

cd C:\dev\triad

## 1. Confirm the CLI exists

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command version

Expected:

TRIAD_CLI_V1

## 2. Run a fast integrity check

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command quick-check

Expected:

TRIAD_QUICK_CHECK_OK

## 3. Run environment and script diagnostics

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command doctor

Expected final token:

TRIAD_DOCTOR_OK

## 4. Run the positive deterministic directory loop

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command full-green

Expected final token:

TRIAD_DIR_FULL_GREEN

## 5. Run the release flow

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command release

Expected final token:

TRIAD_DIR_RELEASE_GREEN

## What release emits

Under proofs\freeze\triad_dir_release_green_<timestamp>\:

- dir_release_transcript.txt
- sha256sums.txt
- triad.dir.release.receipt.json

And under proofs\receipts\:

- triad.ndjson

## Public command surface

- version
- quick-check
- doctor
- full-green
- release
- dir-full-green
- dir-blockmap
- dir-store-export
- dir-restore
- dir-capture-v2
- dir-verify
- archive-reset
- archive-pack
- archive-verify
- archive-extract
- transform-reset
- transform-apply
- transform-verify

## Notes

- Always run from the repo root unless you pass absolute paths.
- TRIAD refuses unsafe overwrite states by design.
- The public entrypoint is scripts\triad_cli_v1.ps1.
- Do not rely on internal runner names for user-facing documentation.
