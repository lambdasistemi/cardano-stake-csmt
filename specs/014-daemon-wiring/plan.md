# Implementation Plan: Daemon Wiring

## Technical Context

- Language/tooling: Haskell, Cabal, Hspec, Fourmolu, Nix flakes with
  `compiler-nix-name = "ghc9123"`.
- Config surface from #23 is already merged in
  `Cardano.StakeCSMT.Application.Run.Config` and `.CLI`.
- Indexer engine from #24 is already merged in
  `Cardano.StakeCSMT.Indexer`.
- Existing HTTP handlers already read stake/history `Database` handles. #25
  wires those handles to the live daemon lifecycle and readiness.

## Design

`run` remains the production entry point. It will:

1. Open stake and history RocksDB once using the paths from `RuntimeConfig`.
2. Load `LedgerConfigBundle` from `configLedgerConfigDir`.
3. Build `ReplayFollowerConfig` from the node socket, network magic, and
   Byron epoch slots.
4. Build a `ReplayCheckpointConfig` from runtime settings with conservative
   behavior that does not modify #24 replay/indexer internals.
5. Create an `IORef Bool` or equivalent readiness signal initialized to
   `False`.
6. Build `QueryHandlers` over the same `Database` handles and the readiness
   action.
7. Start the indexer in a background thread and propagate any indexer failure
   back to the foreground daemon thread.
8. Serve HTTP over the same handlers.

The #24 `withIndexer` helper currently starts a plain `forkIO` thread. If that
shape cannot make indexer death fail the daemon from `Run.Main`, #25 should use
`runIndexer` directly inside `Run.Main` with `forkFinally`/`throwTo` or an
equivalent linked lifecycle. This keeps #24 logic unchanged while satisfying
the issue's fail-closed daemon requirement.

`runtimeHandlers` should stop hardcoding `/ready = True`. Either pass an
explicit readiness action into `runtimeHandlers`, or add a small helper that
constructs handlers with the current readiness signal. Existing scaffold
helpers may keep `unavailableHandlers` for tests and `runHttpServer`, but the
real `run` path must not use unavailable handlers.

## Slice Breakdown

### Slice 1 - Readiness Signal

Introduce the daemon readiness signal in `Run.Main`, thread it into
`QueryHandlers.queryReady`, and update focused tests so `/ready` is false until
the signal is set and true afterward. This slice does not start the real
indexer yet.

Focused gate:

```bash
nix develop --quiet -c just unit "Application.Run"
./gate.sh
```

### Slice 2 - Daemon Indexer Lifecycle

Build ledger/replay/checkpoint config from `RuntimeConfig`, open stake/history
RocksDB once, run the indexer in a linked background thread, and serve HTTP in
the foreground over the same handles. Add an injected/controlled runner test
that writes one epoch into the shared stores, flips readiness through the hook,
and proves an existing query returns real data after indexing. Add an
indexer-death test for failure propagation.

Focused gate:

```bash
nix develop --quiet -c just unit "Application.Run"
./gate.sh
```

### Slice 3 - Concurrent Shared Store Regression

Add a focused unit regression that opens real RocksDB stake/history handles,
performs indexer-style writes while query handlers read the same handles, and
asserts no exceptions, corruption, or torn-read symptoms. Keep the test scoped
to in-process shared handles, not the live devnet HTTP E2E owned by #26.

Focused gate:

```bash
nix develop --quiet -c just unit "Application.Run"
./gate.sh
```

### Slice 4 - Finalization

The ticket orchestrator runs final local gates, updates the PR body with
delivered behavior and verification evidence, drops `gate.sh`, marks the PR
ready only if instructed by the parent process, and reports the PR URL plus
head SHA.

## Verification

- Slice 1: `nix develop --quiet -c just unit "Application.Run"` and
  `./gate.sh`.
- Slice 2: `nix develop --quiet -c just unit "Application.Run"` and
  `./gate.sh`.
- Slice 3: `nix develop --quiet -c just unit "Application.Run"` and
  `./gate.sh`.
- Completion: `just ci` and `nix build .#default`. Run
  `nix build .#e2e-tests` if this ticket changes or adds e2e coverage.

## Risks

- `ReplayCheckpointConfig` requires state save/load callbacks, but the merged
  API does not expose production replay-state serialization. The slice must
  keep daemon wiring usable without widening into #24 replay internals.
- `withIndexer` does not visibly link the child thread to the daemon thread.
  If used unchanged, indexer death would not fail the process; the plan routes
  lifecycle supervision through `Run.Main`.
- The concurrency regression must exercise actual shared RocksDB handles, not
  only in-memory `Database` handles.
