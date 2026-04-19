# How to Run TRIAD v1

## 1. Open PowerShell in the repo root

```powershell
cd C:\dev\triad
2. Run a verified release proof
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command verify-release
3. Review the proof bundle

Inspect the newest directory under:

proofs\freeze\

Key files:

full_green_transcript.txt → full execution log
sha256sums.txt → file integrity inventory
triad.freeze.receipt.json → canonical receipt
4. Archive (package) a folder
powershell.exe -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command archive-reset `
  -ArchiveDir <archive_output_dir>

powershell.exe -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command archive-pack `
  -InputDir <folder_to_package> `
  -ArchiveDir <archive_output_dir>
5. Transform a file
powershell.exe -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command transform-reset `
  -OutputPath <output_file> `
  -ManifestPath <output_file>.transform_manifest.json

powershell.exe -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command transform-apply `
  -TransformType trim_trailing_whitespace `
  -InputPath <input_file> `
  -OutputPath <output_file>
Important Behavior
TRIAD is non-destructive by default
Existing outputs will block execution
You must explicitly reset outputs before rerunning

This ensures:

reproducibility
no silent overwrites
deterministic results