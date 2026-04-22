# TRIAD External Verification Guide v1

This guide shows how to verify TRIAD on a clean machine.

---

## Step 1 — Clone

```powershell
git clone https://github.com/ScrappyHub/triad.git
cd triad
Step 2 — Run
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\scripts\_RUN_triad_full_green_v1.ps1 `
  -RepoRoot .
Step 3 — Validate Output

After execution:

A proof bundle will be created under:
proofs\freeze\
The run should complete without errors
A success token will be printed
Step 4 — Verify Artifacts

Check:

full_green_transcript.txt
sha256sums.txt
triad.freeze.receipt.json

These files must exist and match expected structure.

What This Proves
TRIAD executes deterministically
Outputs are reproducible
Verification requires no mutation
The system is independently verifiable
Failure Conditions

Verification fails if:

any hash mismatch occurs
required files are missing
execution does not complete cleanly
Notes
No network access required
No external dependencies required
Designed to run identically across machines

---

# 🧭 3. RELEASE STRUCTURE (PUBLIC)

Create:


docs\TRIAD_RELEASE_STRUCTURE_V1.md


```markdown
# TRIAD Release Structure v1


triad/
README.md

scripts/
RUN_triad_full_green_v1.ps1
triad_restore.ps1
triad_archive_.ps1
triad_transform_*.ps1

schemas/
*.json

docs/
TRIAD_VERIFY_EXTERNAL_V1.md
TRIAD_RELEASE_STRUCTURE_V1.md

proofs/
freeze/
receipts/
runs/
trust/


---

## Key Components

### scripts/
Deterministic execution and verification logic

### schemas/
Formal data contracts

### proofs/
All verification artifacts and receipts

### docs/
Operator and verification documentation

---

## Design Rule

Everything required to verify TRIAD must exist inside this repository.

No external dependencies are required for validation.
