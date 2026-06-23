# Feature Specification: Live HTTP E2E

**Feature Branch**: `feat/26-live-http-e2e`
**Issue**: #26
**Parent Epic**: #27
**Created**: 2026-06-23
**Status**: Draft

## P1 User Story

As a verifier, against a running devnet and deployed
`cardano-stake-csmt` daemon I can GET `/proof/:credential` over HTTP and
receive the known genesis credential stake plus an inclusion proof that
verifies against the returned epoch root, and I can GET a signed
`/latest-header` whose signature verifies off the wire.

## Acceptance Criteria

- The e2e suite stands up the bundled devnet from `e2e-test/genesis` with
  `Cardano.Node.Client.E2E.Devnet.withCardanoNode`.
- The test launches the real daemon path against that node with network magic
  `42`, the devnet runtime ledger config directory, a temporary RocksDB store,
  a deterministic Ed25519 signing key, and an ephemeral API port.
- The test polls `GET /ready` until `ready = true`, allowing the devnet enough
  time to cross a finalized epoch boundary.
- Over HTTP, the test fetches `/proof/<e2e genesis staking credential>` and
  verifies the returned credential stake equals
  `Coin 30_000_000_000_000_000`.
- The proof returned by `/proof` is decoded from JSON and verified with
  `verifyCredentialProof` against the matching epoch root from `GET /roots`.
- `GET /history-root` returns a non-empty current history root consistent with
  the roots observed after readiness.
- `GET /latest-header` returns a signed latest header, and the test verifies
  the signature from the JSON response rather than trusting in-process values.
- The node and daemon are torn down cleanly, and the API never binds a fixed
  port such as `8080`.
- `nix build .#packages.x86_64-linux.e2e-tests` exercises this live HTTP path.

## Functional Requirements

- **FR-001**: Add an e2e spec that uses the existing bundled genesis directory
  and `withCardanoNode`.
- **FR-002**: Use the existing devnet genesis credential and stake oracle from
  the e2e suite. If the constants are currently local to another e2e module,
  move or copy them into a test-only helper module under `e2e-test`.
- **FR-003**: Start the deployed daemon path by preferring a subprocess launch
  of the built `cardano-stake-csmt` executable with the full CLI:
  `--node-socket`, `--network-magic 42`, `--ledger-config-dir`, `--db`,
  `--signing-key`, and `--api-port`. If Cabal/Nix cannot provide a reliable
  executable path to the test, run the same `Application.Run.Main.run` path in
  a forked thread with a constructed `RuntimeConfig`.
- **FR-004**: All assertions must query the real Servant HTTP server through an
  HTTP client over localhost. In-process WAI session or direct library query
  calls are not sufficient for this ticket.
- **FR-005**: Allocate an ephemeral local port for the API and pass that port to
  the daemon; do not use a fixed port.
- **FR-006**: Poll `/ready` with a bounded timeout suitable for the devnet epoch
  transition; transient startup timing may be retried, but proof assertions
  must be exact.
- **FR-007**: Decode `/proof`, `/roots`, `/history-root`, and `/latest-header`
  JSON into the existing HTTP response types or equivalent test-only decoded
  shapes.
- **FR-008**: Decode the returned proof bytes and root hash using project wire
  codecs, then call `verifyCredentialProof` off the wire.
- **FR-009**: Verify `/latest-header` with the existing HTTP signing verifier.
- **FR-010**: Add only test-only dependency wiring needed for the HTTP client
  or process supervision in the e2e test suite.

## Non-Goals

- No production changes to daemon config, indexer, store wiring, proof formats,
  HTTP handlers, or CLI semantics.
- No mainnet/preprod/preview live sync.
- No throughput or performance benchmark.
- No fixed local port reservation in shared runners.

## Success Criteria

- The focused live HTTP e2e test fails before the daemon is launched/queried
  over HTTP and passes after the test implementation is complete.
- `./gate.sh` passes at the implementation commit.
- Before completion, `just ci` and `nix build .#default .#e2e-tests` pass at
  HEAD.
