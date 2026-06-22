# Implementation Plan: HTTP API And Proofs

## Technical Context

- Language/tooling: Haskell, cabal, Nix dev shell, hspec.
- Existing HTTP scaffold: `http/Cardano/StakeCSMT/HTTP.{API,Server}` currently serves hand-rolled health/readiness responses.
- Reference implementation: `/code/cardano-utxo-csmt` `library http` uses servant, servant-swagger, Swagger UI, JSON response types, CORS, and handler dependency injection.
- Existing proof/root surface: `Cardano.StakeCSMT.CSMT.Builder` and `Cardano.StakeCSMT.History.Builder`.
- Existing storage surface: typed RocksDB adapters for stake CSMT and history columns. The typed KV package exposes cursor iteration through `iterating`, `firstEntry`, `nextEntry`, and `lastEntry`, so HTTP query helpers can list roots and find the latest epoch without changing #6/#7 modules.
- Proof byte format: `CSMT.Hashes.renderProof` produces the CBOR inclusion proof bytes accepted by `CSMT.Hashes.verifyInclusionProof` and `CSMT.Verify.verifyInclusionProof`.
- Signing dependency: prefer the existing `cardano-crypto-class` Ed25519 DSIGN surface (`Ed25519DSIGN`, `SignKeyDSIGN`, `VerKeyDSIGN`, `signDSIGN`, `verifyDSIGN`, raw serialisers) before adding any new crypto dependency.

## Architecture

Replace the scaffold HTTP route model with servant API modules under `Cardano.StakeCSMT.HTTP`:

- `HTTP.Base16`: base16 encode/decode helpers.
- `HTTP.API`: servant API type, response/request wire types, JSON instances, Swagger schema instances.
- `HTTP.Query`: transaction-backed query functions that adapt existing CSMT/history APIs to wire responses.
- `HTTP.Server`: servant server and WAI applications using injected query actions.
- `HTTP.Swagger`: OpenAPI document and Swagger UI server.
- `HTTP.Signing`: deterministic latest-header payload plus Ed25519 signing/verification helpers.

Keep application wiring thin. `Application.Run.Config` should grow only the HTTP/docs ports and optional key/database paths needed to run the service. `Application.Run.Main` should compose the HTTP server with the query functions. Any larger chain-following integration remains outside this ticket.

## Wire Shapes

All hashes, keys, signatures, and proof bytes are base16 text.

`EpochRootResponse`:

- `epoch`
- `stakeRoot`
- `totalStake`

`ProofResponse`:

- `epoch`
- `credential`
- `stake`
- `proofBytes`
- `stakeRoot`
- `totalStake`

`HistoryRootResponse`:

- `historyRoot`

`LatestHeaderResponse` or embedded latest header:

- `epoch`
- `stakeRoot`
- `totalStake`
- `signature`
- `publicKey`

The signed payload is the stable CBOR/byte concatenation of the epoch, stake root bytes, and total stake bytes. It must not use JSON text as the signing payload.

## Slices

### Slice 1: Servant API Types And Wire Codecs

Convert the scaffold `http` library to servant-compatible API and wire types:

- add base16 helpers;
- add response types and JSON/schema instances;
- decode credential path captures from base16 ledger CBOR;
- render hash, coin, epoch, and proof bytes consistently;
- register HTTP/test dependencies and new modules in cabal.

This slice may use stubbed handler tests only; it does not need transaction-backed query behavior yet.

### Slice 2: Query Layer And Proof Handlers

Add transaction-backed query helpers and servant handlers:

- historical proof by `(epoch, credential)`;
- latest proof by newest root entry;
- `/roots` from the root column;
- `/history-root` from the history root column;
- 400/404/503 behavior matching the server contract.

Tests should build small in-memory or RocksDB-backed CSMT/history databases and prove proof bytes verify against returned roots.

### Slice 3: Swagger, Readiness, Metrics, And Application Wiring

Add Swagger UI, `/ready`, `/metrics`, and runnable application composition:

- `HTTP.Swagger`;
- JSON readiness/metrics responses;
- CORS and WAI application exports mirroring `cardano-utxo-csmt`;
- docs/API port config in `Application.Run.Config`;
- executable wiring in `Application.Run.Main`.

Keep this slice focused on serving/wiring. Do not add chain-sync or LSQ behavior.

### Slice 4: Signed Latest Header

Add latest-header signing:

- `HTTP.Signing` with deterministic payload bytes for `(epoch, stakeRoot, totalStake)`;
- Ed25519 sign/verify helpers using `cardano-crypto-class`;
- latest proof/header response includes or exposes the signed latest header;
- tests prove signature verification fails if epoch, stake root, or total stake changes.

This slice may add a small generated/test signing key fixture in test code only.

## Verification

Each implementation slice runs the focused unit test named in its brief and then `./gate.sh` before committing.

The final ticket gate is:

```sh
nix develop -c just ci
```

The ticket owner reruns `./gate.sh` before accepting each implementation commit and reruns the final gate at HEAD before marking the PR complete.
