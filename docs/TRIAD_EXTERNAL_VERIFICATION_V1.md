# TRIAD External Verification v1

## Verification Procedure

1. Clone the TRIAD repository onto a Windows machine with PowerShell 5.1.
2. Run the full-green command.
3. Confirm the success token `TRIAD_TIER0_FULL_GREEN`.
4. Inspect the freeze bundle under `proofs\freeze\triad_tier0_<timestamp>\`.
5. Use `sha256sums.txt` and `full_green_transcript.txt` as the proof surface.

## Verification Rule

Do not treat success text alone as authoritative. The authoritative output is the freeze bundle and its hashes.
