# TRIAD

TRIAD is a deterministic system for **capture, transfer, restore, transform, and verification of data at the byte level**.

It is built to answer one question with certainty:

> Did these bytes change — anywhere, at any stage?

TRIAD provides a local-first, operator-controlled pipeline that makes data movement, reconstruction, and transformation **provable, inspectable, and repeatable**.

---

## What TRIAD Is

TRIAD is not a utility.

It is a **verification system for data integrity across operations**.

It enables:

- byte-faithful capture of data
- deterministic packaging and reconstruction
- controlled transformation with proof
- verification before and after movement
- explicit detection of mismatch or drift
- reproducible execution with audit artifacts

---

## Core Capabilities

### 1. Verified Execution (Release Proof)

Run a full system execution and emit a **canonical proof bundle**:

- full execution transcript
- SHA-256 inventory
- signed receipt of execution state

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command verify-release

Output:

proofs\freeze\
2. Deterministic Archive (Structured Capture)

Capture a folder into a content-addressed archive with manifest proof.

powershell.exe -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command archive-reset `
  -ArchiveDir <archive_output>

powershell.exe -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command archive-pack `
  -InputDir <source_folder> `
  -ArchiveDir <archive_output>

Produces:

content-addressed blobs
manifest
root hash
archive ID
3. Deterministic Transform (Controlled Mutation)

Apply explicit transformations with full traceability.

powershell.exe -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command transform-reset `
  -OutputPath <output_file> `
  -ManifestPath <output_manifest>

powershell.exe -File .\scripts\triad_cli_v1.ps1 `
  -RepoRoot . `
  -Command transform-apply `
  -TransformType trim_trailing_whitespace `
  -InputPath <input_file> `
  -OutputPath <output_file>

Produces:

input hash
output hash
transform ID
manifest
System Guarantees

TRIAD enforces:

no silent mutation
no implicit overwrite
no hidden state
explicit failure on mismatch
deterministic outputs for identical inputs

If something is wrong, TRIAD fails.

Safety Model

TRIAD is intentionally strict.

Existing outputs block execution
Archive directories must be clean
Transforms require explicit reset
No destructive operations occur implicitly

This is required to preserve integrity guarantees.

What TRIAD Is Becoming

TRIAD is the foundation for:

byte-faithful dataset transfer
cross-machine verification
deterministic restore pipelines
drift detection across environments
provable data movement systems

This release provides the verified CLI substrate for those capabilities.

Environment
Windows PowerShell 5.1
UTF-8 (no BOM)
LF line endings
StrictMode enabled
non-interactive execution
Operator Model

TRIAD is:

local-first
explicit
non-automated
operator-controlled

It does not act without direct invocation.

Output Philosophy

Every operation produces artifacts that can be:

inspected
hashed
compared
reproduced

Nothing is hidden.

Release Scope

This release includes:

verified CLI entrypoint
archive capture (pack)
deterministic transforms
full-system proof execution

Additional capabilities (restore validation, transfer pipelines, extended verification) are built on this foundation.

Usage Constraint

Use TRIAD only on systems and data you own or are explicitly authorized to operate on.

Summary

TRIAD is a system for proving what happened to data.

Not assuming.
Not trusting.
<<<<<<< HEAD
Proving.
=======
Proving.
>>>>>>> 843463f (TRIAD DIR Tier-0 RELEASE GREEN (freeze bundle + negative enforcement + receipts))
