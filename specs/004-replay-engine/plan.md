# Implementation Plan: Replay Engine

## Existing Context

Issue #3 added `Cardano.StakeCSMT.Ledger.Config`, which loads the node
genesis files and exposes:

- `ledgerConfigGenesisState :: ExtLedgerState StakeBlock ValuesMK`
- `ledgerConfigTopLevelConfig :: TopLevelConfig StakeBlock`
- `ledgerConfigEpochAt :: LedgerConfigBundle -> Word64 -> IO Word64`

The consensus replay primitive is:

```haskell
tickThenReapply
    :: ApplyBlock l blk
    => ComputeLedgerEvents
    -> LedgerCfg l
    -> blk
    -> l ValuesMK
    -> l DiffMK
```

For this project, use it as:

```haskell
tickThenReapply
    OmitLedgerEvents
    (ExtLedgerCfg ledgerConfigTopLevelConfig)
    block
    previousExtLedgerState
```

Then convert the diff state back to values with `applyDiffs previous diff`.

## Public API Shape

`Cardano.StakeCSMT.Ledger.Replay` should expose a small, stable surface:

- `ReplayState`, with current ledger state and last observed epoch.
- `EpochTransition`, with previous epoch, current epoch, and slot.
- `initialReplayState :: LedgerConfigBundle -> IO ReplayState`
- `replayBlock :: LedgerConfigBundle -> (EpochTransition -> IO ()) -> ReplayState -> StakeBlock -> IO ReplayState`
- `ReplayFollowerConfig`, carrying socket path, network magic, Byron epoch
  slots, and optional tracers as needed by the N2C helper.
- `runReplayFollower` or `withReplayFollower`, using N2C ChainSync from
  Origin and threading `ReplayState`.

Names can change if the implementation finds a clearer local pattern, but
the module must remain small and documented.

## Dependency Plan

Add only what `Replay` needs:

- `cardano-node-clients` for `Cardano.Node.Client.N2C.ChainSync` and
  full-block `Fetched` values.
- `chain-follower` for `Follower`, `Intersector`, and
  `ProgressOrRewind`.
- Consensus/network packages only when imports require them, such as
  `ouroboros-network-api`, `cardano-chain`, `stm`, `async`, or
  `contra-tracer`.

If `cardano-node-clients` or `chain-follower` are not available from CHaP,
reuse the source-repository-package pins from `/code/cardano-utxo-csmt`
rather than changing the existing Cardano ledger closure.

## Slice Breakdown

### Slice 1: Pure Replay Core

Add the `Replay` module with `ReplayState`, `EpochTransition`,
`initialReplayState`, and `replayBlock`. Unit tests should prove:

- the initial state comes from `ledgerConfigGenesisState`;
- repeated blocks or synthetic slot observations inside the same epoch do
  not duplicate callbacks;
- moving to a later epoch fires exactly one callback for that observed
  transition.

If constructing real blocks is too expensive for the callback tests,
factor a small pure epoch-transition helper and cover it directly, while
still compiling `replayBlock` against the real consensus types.

### Slice 2: N2C Follower Wiring

Add the follower config and ChainSync integration. The follower should:

- request Origin as its cold start point;
- use `mkChainSyncN2C` and `runChainSyncN2C`;
- handle roll-forward by replaying `fetchedBlock`;
- thread the updated `ReplayState` through the returned `Follower`;
- avoid LSQ in the production path.

Rollback persistence remains out of scope. On rollback, either reset the
in-memory replay state to genesis/Origin or return a documented unsupported
rollback path that future ticket #8 can replace.

### Slice 3: Devnet Replay Proof

Add a focused e2e or integration-style test that starts from the existing
devnet genesis configuration and replays a devnet ChainSync stream to tip
without error. Prefer existing `cardano-node-clients` devnet helpers if
available. The test should verify that at least one block was replayed and
that no epoch callback is duplicated.

## Verification

- Focused slice commands:
  - `nix develop --quiet -c just unit "Ledger.Replay"`
  - `nix develop --quiet -c just e2e`
- Full gate:
  - `./gate.sh`
- Final required command:
  - `nix develop -c just ci`
