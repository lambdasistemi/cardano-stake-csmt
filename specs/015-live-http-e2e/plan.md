# Implementation Plan: Live HTTP E2E

## Technical Context

- Language/tooling: Haskell, Cabal, Hspec, Fourmolu, Nix flakes with
  `compiler-nix-name = "ghc9123"`.
- #23, #24, and #25 are already merged into `origin/main`; the executable now
  has real daemon CLI/config, indexer lifecycle, atomic single-store writes,
  readiness, and HTTP handlers backed by the live store.
- Existing e2e modules already stand up the bundled devnet and prove in-process
  replay/indexer behavior. This ticket must prove the HTTP boundary and signed
  daemon response.
- The e2e suite currently has no HTTP client dependency. Adding a test-only
  client dependency is in scope.

## Design

Add `Cardano.StakeCSMT.E2E.LiveHTTPSpec` under `e2e-test` and register it in
the `e2e-tests` suite.

The spec should:

1. Start the bundled devnet with `withCardanoNode genesisDir`.
2. Allocate a free localhost port by binding an ephemeral socket, read the
   assigned port, close the socket, then immediately launch the daemon on that
   port.
3. Write a deterministic Ed25519 signing key to a temporary file using the
   same serialization style covered by `Application.RunSpec`.
4. Prefer launching the built `cardano-stake-csmt` executable as a subprocess
   with:

   ```text
   --node-socket <devnet socket>
   --network-magic 42
   --ledger-config-dir <node runtime dir>
   --db <temporary db path>
   --signing-key <temporary key file>
   --api-port <ephemeral port>
   ```

   If the e2e test cannot reliably discover the built executable path, fork
   `Cardano.StakeCSMT.Application.Run.Main.run` in a thread with an equivalent
   `RuntimeConfig`. This fallback still exercises the same daemon run path and
   the real Warp/Servant HTTP server.

5. Poll `GET /ready` until it returns `ReadyResponse{ready = True}` or a
   timeout expires. The existing devnet specs use 75 seconds for epoch
   transition capture; use that as the lower bound and keep the timeout
   bounded.
6. Render the known e2e genesis staking credential as base16, request
   `/proof/<credential>`, and assert the returned stake equals
   `e2eGenesisStake`.
7. Request `/roots`, find the root for the proof epoch, decode the root/proof
   from wire JSON, and call `verifyCredentialProof` with the returned stake and
   proof.
8. Request `/history-root` and assert it is non-empty. It should be present
   only after the daemon is ready and roots are available.
9. Request `/latest-header`, verify it with `verifyLatestHeader`, and assert it
   refers to the same latest root/epoch observed from `/roots`.
10. Ensure daemon shutdown happens even on assertion failure.

## Owned Files

- `e2e-test/main.hs`
- `e2e-test/Cardano/StakeCSMT/E2E/LiveHTTPSpec.hs`
- Optional new test-only helper module under `e2e-test/Cardano/StakeCSMT/E2E/`
- `cardano-stake-csmt.cabal` only for `e2e-tests` `other-modules` and
  test-only dependencies
- `specs/015-live-http-e2e/*` for task stamping during acceptance

## Forbidden Scope

- No edits under `lib/`, `http/`, `application/`, `executables/`, or `test/`
  unless the ticket orchestrator writes and receives a BLOCKED answer from the
  epic owner.
- No production config, CLI, indexer, store, or HTTP handler changes.
- No fixed API port.
- No alternate GHC/toolchain.
- No weakening or skipping existing e2e replay/indexer tests.

## Slice Breakdown

### Slice 1 - Live HTTP Proof

Add the live HTTP e2e spec and any test-only helper/dependency wiring needed to
start the daemon, poll readiness, query all required HTTP endpoints, verify the
credential proof off the wire, and verify the latest-header signature.

Focused gate:

```bash
nix develop --quiet -c just e2e
./gate.sh
```

### Finalization

The ticket orchestrator runs the full local gates, updates the PR body with
verification evidence, drops `gate.sh`, marks the PR ready, and reports the PR
URL plus head SHA to the epic owner. The epic owner merges.

## Verification

- Slice 1: `nix develop --quiet -c just e2e` and `./gate.sh`.
- Completion: `just ci` and `nix build .#default .#e2e-tests`.

## Risks

- Built executable discovery may be awkward from a Cabal test environment. The
  accepted fallback is to fork the same `Application.Run.Main.run` entrypoint
  while still querying the real HTTP server over localhost.
- Releasing an ephemeral port before daemon bind has a small race. The e2e
  runner is local and single-process, so this is acceptable; a retry around
  daemon startup is allowed if needed.
- The devnet epoch transition is slow and can be timing-sensitive on shared
  runners. Keep startup/readiness polling bounded and diagnostic.
- If the live HTTP path reveals a daemon bug, stop and write a BLOCKED Q-file
  instead of patching production code inside this ticket.
