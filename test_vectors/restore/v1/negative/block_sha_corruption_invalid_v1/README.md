# TRIAD Restore Positive Vector

Vector id: `locked_green_restore_vector`

This vector is seeded from the latest validated TRIAD green freeze.

Locked facts:

- snapshot_id: `0e26f315c83ee36d222b26cb4134c50a8fd430b593e6e39bbc31dc1b4cf6fd78`
- payload sha256: `a351162b9fda82bb8610b8194192b1d6f2dcc5b29a677e55d6cd34ba5ac9b536`
- payload length: `3670016`
- payload block root: `9e4f1dc230da7632b11b03b8bc0d721dcacfdb474de2ae77ebeadeff8324849f`
- payload block count: `4`

Restore contract:

- payload file entry is authoritative
- payloadEntry.blocks is authoritative
- replay uses index + offset + size
- repeated block reuse is valid
- naive unique .blk concatenation is invalid
