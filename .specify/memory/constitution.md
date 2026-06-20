# Cardano Stake CSMT Constitution

## Core Principles

### I. ChainSync Boundary

N2C ChainSync from Origin only; no LSQ in production path. Production chain following must use the local node-to-client interface from genesis so epoch snapshots and rollback handling are derived from one trusted chain view.

### II. Trusted Ledger Application

Trusted-chain block application via reapply, not full validation. The service consumes blocks from a trusted node and applies them through the ledger state transition path appropriate for replaying trusted blocks.

### III. Stake Snapshot Source

Snapshot source is ledger ssStake at epoch boundary. Stake distribution inputs must come from the ledger snapshot for the completed epoch, not from ad hoc queries or reconstructed partial views.

### IV. History And Finality

History leaf carries (epoch, stakeRoot, totalStake). Finalized epoch roots deeper than k are immutable. Any root shallower than k must be treated as rollback-sensitive until the chain finality window has passed.

### V. CSMT Compatibility

CSMT roots/proofs use mts:csmt and verify against aiken-csmt. Root and proof encodings must remain compatible with the on-chain verifier target and its expected tree semantics.

## Engineering Boundaries

Pure core / impure shell. Pure modules own stake snapshots, history leaves, CSMT root construction, proof construction, and verification-facing data types. Impure modules own node connections, scheduling, storage, logging, and HTTP delivery.

The implementation must keep scaffold documentation factual. Documentation may describe planned architecture, but must not claim that ledger extraction, CSMT construction, or proof generation exists before those slices land.

## Workflow

One bisect-safe commit per slice, Nix-first CI, no unreviewed skips. Each slice must prove RED before GREEN, hand off diffs for navigator review, and run the local gate before commit. CI and local checks should use the Nix flake and development shell as the authoritative environment.

## Governance

This constitution records the issue #1 invariants and workflow rules for the stake CSMT service. Changes require an explicit issue or review decision, updated documentation, and verification that specs, tasks, CI, and implementation still align.

**Version**: 1.0.0 | **Ratified**: 2026-06-20 | **Last Amended**: 2026-06-20
