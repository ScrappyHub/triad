# TRIAD Restore Workflow v1 (Prepare → Verify → Commit)

This document locks the **restore workflow contract** for TRIAD.

## Goal
Restore is a 3-step transactional workflow:

1. **Prepare**
   - Build a temp output from snapshot blocks
   - Emit a restore plan file (`triad.restore_plan.v1`) that binds:
     - SnapshotDir + ManifestPath
     - OutFile + TmpFile
     - Expected length + expected SHA-256 + expected block_root

2. **Verify**
   - Validate snapshot integrity:
     - Every `blocks/<sha>.blk` file hashes to `<sha>`
     - Re-derive Merkle `block_root` from the ordered block list and compare to manifest
   - Validate prepared temp output:
     - Tmp length matches manifest
     - Tmp SHA-256 matches manifest

3. **Commit**
   - Move tmp → OutFile (replace if exists)
   - Commit does not re-verify; caller must run Verify first.

## Scripts (v1)
- scripts\triad_restore_prepare_v1.ps1
- scripts\triad_restore_verify_v1.ps1
- scripts\triad_restore_commit_v1.ps1
- scripts\_selftest_triad_restore_workflow_v1.ps1
