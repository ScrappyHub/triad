# TRIAD Restore Stress Seed v1

This directory seeds the first restore stress harness from the validated TRIAD green baseline.

Locked baseline:

- snapshot_id: `0e26f315c83ee36d222b26cb4134c50a8fd430b593e6e39bbc31dc1b4cf6fd78`
- payload sha256: `a351162b9fda82bb8610b8194192b1d6f2dcc5b29a677e55d6cd34ba5ac9b536`
- payload length: `3670016`
- payload block root: `9e4f1dc230da7632b11b03b8bc0d721dcacfdb474de2ae77ebeadeff8324849f`
- payload block count: `4`
- restored sha256: `a351162b9fda82bb8610b8194192b1d6f2dcc5b29a677e55d6cd34ba5ac9b536`

Locked contract:

- payload file entry inside `snapshot.tree.manifest.json` is authoritative
- payloadEntry.blocks is authoritative for reconstruction
- replay uses index + offset + size
- repeated block reuse is valid
- naive unique `.blk` concatenation is invalid

Initial stress order:

1. locked green baseline
2. repeated block reuse
3. tail partial block
4. naive unique block concat negative
5. block sha corruption negative
6. payload sha mismatch negative
7. missing block file negative
8. deeper tree seed
9. multi-file seed
