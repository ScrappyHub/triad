# TRIAD Tree Transcript Spec v1 (Stub)

This document locks the **minimal transcript stub** for TRIAD tree snapshots.

## Goal
Add an append-only, hash-chained transcript to every tree snapshot, so later layers (RunLedger/NFL/Watchtower)
can ingest events deterministically without changing the engine.

## Files in SnapshotDir (additional)
- `transcript.ndjson` (UTF-8 no BOM, LF)
- `snapshot.transcript_root` (UTF-8 no BOM, LF) — contains a single 64-hex digest

## transcript.ndjson line schema (v1)
Each line is a single JSON object with **stable field order**:

`{ seq, ts_utc, event, prev_sha256, data_json, sha256 }`

Where:
- `seq` is 1-based monotonically increasing
- `ts_utc` is ISO-8601 UTC timestamp
- `event` is an event string (e.g. `capture.start`)
- `prev_sha256` is the previous line hash (genesis = 64 zeros)
- `data_json` is a compact JSON string (may be empty string)
- `sha256` is the line hash (hex)

## Line hash (v1)
`sha256 = SHA256( UTF8("triad.transcript_line.v1|<seq>|<ts_utc>|<event>|<prev_sha256>|<data_json>") )`

## transcript_root (v1)
`transcript_root = MerkleRoot( [ line.sha256 in transcript order ] )`

Merkle rules:
- leaves are 32-byte digests
- pairwise SHA-256 over concatenated digests
- duplicate last digest if odd count

## Manifest binding (v1)
Tree manifest roots include:

`roots.transcript_root = <transcript_root>`

and:

`transcript.path = "transcript.ndjson"`
`transcript.root_path = "snapshot.transcript_root"`

## Canonical selftest
- `scripts\_selftest_triad_tree_transcript_v1.ps1`
  - captures a deterministic tree
  - validates chain (`prev_sha256`)
  - re-derives each line hash
  - re-derives `transcript_root` and compares to manifest + root file
