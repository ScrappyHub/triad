# TRIAD Engine Spec v1 (File-based Capture/Restore Baseline)

This document locks the **initial instrument baseline** for TRIAD engine behavior.
It is intentionally minimal and deterministic.

## Scope (v1)
- Capture a single **input file** into a content-addressed snapshot directory.
- Restore that snapshot back into a single **output file**.
- Verify: length + SHA-256 roundtrip equality.
- Bind artifacts to the repo’s **NeverLost identity** (principal, key_id, pubkey).

## Snapshot Layout (v1)
SnapshotDir/
- snapshot.manifest.json
- blocks/
  - <sha256>.blk

## Manifest Schema (v1)
`schema = "triad.snapshot.v1"`

Required top-level fields:
- schema
- snapshot_id
- created_utc
- identity: { principal, key_id, pubkey }
- source: { input_file_name, length, sha256 }
- chunking: { block_size }
- roots: { block_root }
- blocks[]: ordered list of blocks in read order:
  - index, offset, size, sha256, path ("blocks/<sha256>.blk")

## Block Root (v1)
- Merkle root over block hashes in *block order*.
- Pairwise SHA-256 over concatenated 32-byte digests; duplicate last digest on odd count.

## SnapshotId (v1)
`sha256("triad.snapshot.v1|<block_size>|<length>|<file_sha256>|<block_root>")`

## Transactional Restore (v1)
- Restore writes to a temp file first.
- Verify length + SHA-256 against manifest.
- Commit by atomic move to final output path (replacing if present).

## Canonical Scripts (v1)
- scripts\triad_capture_v1.ps1
- scripts\triad_restore_v1.ps1
- scripts\_selftest_triad_roundtrip_v1.ps1

## Next Locks (v2+)
- Directory capture (trees), semantic root, transcript root, policy hash binding.
- Prepare→Verify→Commit restore workflow across directory trees.
- Attestation + Watchtower/NFL publish boundaries.
