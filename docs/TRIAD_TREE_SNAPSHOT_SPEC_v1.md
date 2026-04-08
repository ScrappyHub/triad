# TRIAD Tree Snapshot Spec v1 (Directories + Files)

This document locks the **tree capture/restore baseline** for TRIAD (v1).

## Scope (v1)
- Capture a directory tree (directories + files) into a snapshot directory.
- Store file content as content-addressed blocks (SHA-256) under `blocks/`.
- Store a deterministic manifest describing the tree and the block lists.
- Restore via **Prepare → Verify → Commit** into an output directory.
- Verify:
  - Every block hashes to its filename sha256
  - `block_root` re-derives from the set of unique blocks
  - `semantic_root` re-derives from entry records in manifest order
  - Restored files match manifest sha/length
  - Empty directories are preserved
- Bind manifest identity to repo’s NeverLost identity.

## Snapshot Layout (v1)
SnapshotDir/
- snapshot.tree.manifest.json
- blocks/
  - <sha256>.blk

## Manifest Schema (v1)
`schema = "triad.snapshot_tree.v1"`

Top-level:
- schema
- snapshot_id
- created_utc
- identity: { principal, key_id, pubkey }
- source: { input_dir_name, files, dirs, total_bytes }
- chunking: { block_size }
- roots: { semantic_root, block_root }
- entries[] (in deterministic order):
  - type = "dir": { type, path }
  - type = "file": { type, path, length, sha256, roots:{block_root}, blocks[] }

Blocks in a file:
- blocks[] is ordered in read order:
  - index, offset, size, sha256, path ("blocks/<sha256>.blk")

## Entry Hash (v1)
For semantic integrity:
`entry_hash = sha256("triad.tree.entry.v1|<type>|<path>|<length>|<sha256>")`
- dirs: length=0, sha256=""

## semantic_root (v1)
Merkle root over **entry_hash** in manifest entry order.

## block_root (v1)
Merkle root over **unique** block sha256 values sorted lexicographically.

## snapshot_id (tree v1)
`sha256("triad.snapshot_tree.v1|<block_size>|<files>|<dirs>|<total_bytes>|<semantic_root>|<block_root>")`

## Restore Workflow (v1)
- Prepare: materialize tmp restore dir + write plan (`triad.restore_tree_plan.v1`)
- Verify: validate blocks, roots, tmp file hashes/lengths
- Commit: replace OutDir by moving tmp dir into place
