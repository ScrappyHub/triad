# TRIAD GREEN FREEZE

freeze_id: triad_restore_green_20260308_004739_0e26f315c83e
snapshot_id: 0e26f315c83ee36d222b26cb4134c50a8fd430b593e6e39bbc31dc1b4cf6fd78
payload_sha256: a351162b9fda82bb8610b8194192b1d6f2dcc5b29a677e55d6cd34ba5ac9b536
freeze_dir: C:\dev\triad\proofs\freeze\triad_restore_green_20260308_004739_0e26f315c83e

## Product surface hashes
- triad_restore_verify_v1.ps1: 8d83632ef532939f6441105c325fe9117c41975501129dfd870ad17970c8015f
- triad_restore_prepare_v1.ps1: cbc5533888251f21962eb48e59acd8d42cabc39feedf5dfa808d938320897550
- triad_restore_commit_v1.ps1: 8dd5f68a3bab86268f45b0958a3ccf2af55934cd4e499efdab939c8de4a57d3e
- _selftest_triad_restore_workflow_v1.ps1: f0fd7659387e11f8ed8a58d80941debe9c148e663178454dc2024c2a0d46ff7e
- snapshot.tree.manifest.json: 288872f16bc5901f6529034f972550b3f48d215979e2a1f068ec07a0eb6d7a0b
- selftest_transcript.txt: 4b32b104d22cb8b85a3253819c6936c2daa8b11d42f9d58cc73296cc428c190e

## Locked restore contract
- payload file entry is authoritative
- payloadEntry.blocks is authoritative for reconstruction
- restore replays blocks by index + offset + size
- repeated block reuse is valid
- naive concatenation of unique .blk files is invalid

## PASS tokens required
- TRIAD RESTORE VERIFY v1
- TRIAD RESTORE COMMIT v1
- TRIAD RESTORE WORKFLOW SELFTEST: PASS


## FREEZE VALIDATION
- exit_code: 0
- transcript_hash: d6810734badb402cde846564af5e4102ba8f53dcf823ef0b74aa2227e26b8b2b
- stdout_hash: 543b0e2d5c349e53d7f5bfd861e6625baa445988c3003d1e1c2f44ea9f1854d2
- stderr_hash: 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b
- result: FREEZE_VALIDATED_OK
