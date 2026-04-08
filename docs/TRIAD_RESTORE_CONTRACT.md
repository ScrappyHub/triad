# TRIAD Restore Contract

## Canonical rule

For tree manifests, the payload file entry inside `snapshot.tree.manifest.json` is authoritative for reconstruction and verification.

## Authoritative source of truth

The payload file entry defines:

- payload path
- payload length
- payload sha256
- payload block root
- ordered block replay map

## Reconstruction rule

Reconstruction uses `payloadEntry.blocks`.

Each block item is interpreted as:

- `index`
- `offset`
- `size`
- `sha256`
- `path`

Restore correctness requires replay by offset and size, not naive concatenation.

## Required behavior

TRIAD verify / commit must:

1. locate the authoritative payload file entry
2. read expected length from the payload file entry
3. read expected sha256 from the payload file entry
4. read expected block root from the payload file entry roots
5. validate referenced block files by sha256
6. rebuild tmp/output by replaying blocks using offset and size
7. permit repeated block reuse
8. validate final tmp/output length and sha256 against payload entry expectations

## Explicit non-rule

The following is invalid:

- concatenating only unique `.blk` files
- assuming manifest top-level source total_bytes is sufficient for payload verification
- assuming manifest top-level roots block_root is the payload block root for reconstruction
- assuming missing top-level `manifest.blocks` means payload reconstruction cannot proceed

## Tree manifest interpretation

For tree manifests:

- top-level manifest describes snapshot tree structure
- payload file entry describes file reconstruction contract
- payload file entry roots are the file-level roots used for verify/commit
- payload file entry blocks are the replay map used for reconstruction

## Proven working example

Validated working example currently locked:

- snapshot_id: `0e26f315c83ee36d222b26cb4134c50a8fd430b593e6e39bbc31dc1b4cf6fd78`
- payload sha256: `a351162b9fda82bb8610b8194192b1d6f2dcc5b29a677e55d6cd34ba5ac9b536`

## Why this contract matters

This is the restore substrate relied on by:

- TRIAD itself
- Atlas Artifact integration
- Legacy Doctor integration
