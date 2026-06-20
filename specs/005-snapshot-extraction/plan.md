# Snapshot Extraction Plan

## Technical Shape

Add `Cardano.StakeCSMT.Ledger.StakeSnapshot` in the existing `library` component. The module owns a pure data boundary:

```haskell
data StakeSnapshot = StakeSnapshot
    { stakeSnapshotStake :: Map (Credential 'Staking) Coin
    , stakeSnapshotTotalStake :: Coin
    }

data StakeSnapshotError = StakeSnapshotByronEra

stakeSnapshotFromLedgerState
    :: ExtLedgerState StakeBlock ValuesMK
    -> Either StakeSnapshotError StakeSnapshot
```

The implementation should take `ledgerState` from `ExtLedgerState`, match the current Cardano era with `LedgerStateByron`, `LedgerStateShelley`, `LedgerStateAllegra`, `LedgerStateMary`, `LedgerStateAlonzo`, `LedgerStateBabbage`, `LedgerStateConway`, and `LedgerStateDijkstra`, then use `shelleyLedgerState` for every Shelley-based branch.

For each Shelley-based `NewEpochState`, extract:

```haskell
stake = ssStake (ssStakeMark (esSnapshots (nesEs nes)))
```

Materialize `unStake stake` into a strict `Map (Credential 'Staking) Coin` with `Data.VMap.toMap` and `fromCompact`. Compute `totalStake` from the same `Stake` value, preferably with `sumAllStake`.

## Cabal Surface

Register the new module as an exposed module of `library`. Add only component-level dependencies required by imports, such as `containers`, if the final code needs them. Do not change `cabal.project`, SRPs, `flake.*`, or Nix closure files.

## Tests

Add `test/Cardano/StakeCSMT/Ledger/StakeSnapshotSpec.hs` and import it from `test/main.hs`.

The focused test loads `test/fixtures/devnet-genesis` with `loadLedgerConfig`, extracts from `ledgerConfigGenesisState`, and checks:

- extraction succeeds for the Shelley-based genesis state,
- the snapshot contains the known genesis stake credential,
- `totalStake` equals the sum of the returned credential stake map,
- the total matches the known devnet genesis delegated funds.

If the exact credential constructor is cumbersome, assert the single-entry map and total from the decoded ledger state rather than string-rendering the credential.

## Slice Plan

One vertical slice is sufficient:

- Slice 1: implement the module, register it, add unit coverage, run the focused unit test and `./gate.sh`, and commit.

## Verification

Per-slice:

```bash
nix develop -c just unit "Ledger.StakeSnapshot"
./gate.sh
```

Before completion:

```bash
nix develop -c just ci
```
