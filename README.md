# TRIAD

TRIAD is a deterministic filesystem capture, block-store export, restore, and verification instrument.

It is designed to prove one thing clearly:

> Did the restored data match the original exactly, and do tampered states fail deterministically?

TRIAD is local-first, explicit, and operator-controlled.

## Public CLI

All public operation routes through:

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command <command>

Core public commands:

- version
- quick-check
- doctor
- full-green
- release

## What full-green does

full-green runs the deterministic positive directory loop:

1. directory blockmap
2. block store export
3. restore from block store
4. capture original
5. capture restored
6. verify identical

Expected success token:

TRIAD_DIR_FULL_GREEN

## What release does

release runs:

- the full positive directory loop
- missing block negative
- tampered block negative
- tampered manifest negative
- freeze bundle emission
- sha256sums generation
- receipt emission
- append-only NDJSON receipt update

Expected success token:

TRIAD_DIR_RELEASE_GREEN

## Quick Start

Version:

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command version

Quick Check:

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command quick-check

Doctor:

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command doctor

Full Green:

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command full-green

Release:

powershell -File .\scripts\triad_cli_v1.ps1 -RepoRoot . -Command release

## Release Artifacts

A successful release writes:

- a freeze directory under proofs\freeze\
- dir_release_transcript.txt
- sha256sums.txt
- triad.dir.release.receipt.json
- an append-only line in proofs\receipts\triad.ndjson

## Current CLI Status

The CLI surface currently proves:

- TRIAD_CLI_V1
- TRIAD_QUICK_CHECK_OK
- TRIAD_DOCTOR_OK
- TRIAD_DIR_FULL_GREEN
- TRIAD_DIR_RELEASE_GREEN

## Safety Model

TRIAD is strict on purpose:

- no silent overwrite
- no implicit mutation
- deterministic failure on tamper
- explicit operator invocation only

## Scope

TRIAD currently exposes a sealed CLI surface for deterministic directory capture, block-store export, restore, verification, and release evidence generation.

UI and higher-layer integrations come after the CLI remains stable.
