# Feature Specification: HTTP API And Proofs

## P1 User Story

As a verifier, I can request a stake proof for a staking credential and receive a self-verifying CSMT proof plus the committed epoch root and total stake needed to validate voting power.

## Scope

Build the user-facing HTTP service for stake CSMT data. The service mirrors the servant/swagger shape used by `cardano-utxo-csmt`, adapted from UTxO keys to staking credentials and epoch roots.

The HTTP layer consumes the existing #6 CSMT and #7 history APIs:

- `buildCredentialProof`, `queryEpochRoot`, and `verifyCredentialProof`;
- `buildEpochRootProof`, `queryHistoryLeaf`, `queryHistoryRoot`, and `verifyEpochRootProof`;
- the stable `credentialCodec`, `coinCodec`, `epochNoCodec`, and `EpochRoot` model.

The HTTP work is limited to serving, query adaptation, wire formats, application wiring, tests, and a small latest-header signing surface. It must not change `Cardano.StakeCSMT.CSMT.*`, `Cardano.StakeCSMT.History.*`, or `Cardano.StakeCSMT.Ledger.*` schemas/behavior beyond consuming public APIs.

## User Stories

1. As a verifier, I can call `GET /proof/:credential` and receive the latest available credential stake proof with the epoch, stake root, and total stake committed by that epoch.
2. As a verifier, I can call `GET /proof/:epoch/:credential` and receive the same proof for a historical epoch.
3. As a verifier, I can call `GET /roots` and receive every known epoch root, including each epoch's `totalStake`.
4. As a verifier, I can call `GET /history-root` and receive the current history root that commits historical epoch leaves.
5. As an operator, I can call `/ready`, `/metrics`, and Swagger UI endpoints to inspect service health and API shape.
6. As an off-chain voting client, I can verify that the latest-epoch header `(epoch, stakeRoot, totalStake)` was signed by the configured institution key.

## Functional Requirements

- FR-001: The `http` library MUST expose a servant API with `/proof/:credential`, `/proof/:epoch/:credential`, `/roots`, `/history-root`, `/ready`, `/metrics`, and Swagger UI.
- FR-002: Credential path captures MUST be base16 ledger-CBOR bytes decoded with `credentialCodec`; invalid base16 or invalid credential CBOR MUST return HTTP 400.
- FR-003: Proof responses MUST include the epoch, credential, stake amount, proof bytes as base16, stake root hash as base16, and total stake.
- FR-004: `proofBytes` MUST be the CBOR proof byte format accepted by `CSMT.Hashes.verifyInclusionProof` or the matching `csmt-verify` verifier.
- FR-005: `GET /proof/:credential` MUST use the latest known epoch root from the stake CSMT root column.
- FR-006: `GET /proof/:epoch/:credential` MUST return HTTP 404 when the epoch root or credential proof is missing.
- FR-007: `GET /roots` MUST return per-epoch roots sorted by epoch, each carrying `epoch`, `stakeRoot`, and `totalStake`.
- FR-008: `GET /history-root` MUST return the current history root, or HTTP 404 when no history root exists.
- FR-009: `/ready` MUST expose service readiness as JSON and MUST not be gated on proof data being present.
- FR-010: `/metrics` MUST expose a minimal JSON snapshot appropriate to the current application state; richer chain-following metrics can be added later without breaking the endpoint.
- FR-011: Swagger UI MUST serve an OpenAPI document for the API types.
- FR-012: The latest-epoch header MUST serialize `(epoch, stakeRoot, totalStake)` deterministically and include an Ed25519 signature plus public key bytes in base16.
- FR-013: Tests MUST prove that proof responses verify against the committed root and that signed latest headers verify against the public key.

## Non-Goals

- No `aiken-csmt` verifier changes.
- No LSQ production path.
- No CSMT, history, rollback, or ledger schema changes.
- No mainnet bootstrap tuning.
- No DRep or pool-level voting-power endpoints.

## Acceptance Criteria

- AC-001: Unit tests cover JSON codecs, credential/base16 decoding, API routing, and Swagger generation.
- AC-002: Unit or RocksDB-backed tests prove `/proof/:epoch/:credential` returns proof bytes that verify against the returned `stakeRoot`.
- AC-003: Unit or RocksDB-backed tests prove `/proof/:credential` selects the newest epoch root.
- AC-004: Tests prove `/roots` and `/history-root` reflect persisted CSMT/history data without modifying #6/#7 modules.
- AC-005: Tests prove invalid credentials return 400 and missing roots/proofs return 404.
- AC-006: Tests prove latest-header signing/verification covers epoch, stake root, and total stake.
- AC-007: `nix develop -c just ci` passes before the PR is marked complete.
