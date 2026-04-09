- Reproducible proof artifacts
- Local-first operation (no network required)
- Independent verification on clean machines

---

## Environment

- Windows PowerShell 5.1
- UTF-8 (no BOM), LF line endings
- StrictMode enabled
- Non-interactive execution

---

## Run TRIAD

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\scripts\_RUN_triad_full_green_v1.ps1 `
  -RepoRoot .


---

# Expected Result

A successful run will:

Execute all verification workflows
Produce a complete proof bundle under:
proofs\freeze\
Emit a success token indicating a verified full-system run
Proof Artifacts

Each run produces:

Execution transcript
SHA-256 integrity file
Freeze receipt
Deterministic output artifacts

These artifacts can be copied and verified independently.

Independent Verification

TRIAD can be validated on a clean machine by:

Cloning the repository
Running the command above
Comparing generated proof artifacts

No external services or dependencies are required.

Design Principles
Determinism first
Verification over trust
Local-first execution
No hidden state
Reproducible outcomes
Status

This is the first verified standalone release of TRIAD.
