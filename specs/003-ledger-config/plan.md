# Implementation Plan: Ledger Config

## Technical Context

- Language: Haskell, GHC 9.12.3 through the repository Nix dev shell.
- Build/test entrypoint: `./gate.sh`, which runs `nix develop --quiet -c just ci`.
- Component boundary: public named `library` component.
- Target module: `Cardano.StakeCSMT.Ledger.Config`.
- Cardano block alias: `CardanoBlock StandardCrypto`.
- Primary API: `Ouroboros.Consensus.Cardano.Node.protocolInfoCardano`.

## Design

Add a `Ledger.Config` module that centralizes genesis bootstrap for later
ledger replay code. The module should expose a small, stable project
surface rather than leaking every consensus constructor to downstream
modules.

Expected public shape:

- `type Block = CardanoBlock StandardCrypto`
- `LedgerConfigPaths`, naming node config and genesis files, with a
  helper for the common node-config-relative layout.
- `LedgerConfigBundle`, containing:
  - `ProtocolInfo IO Block`
  - `ExtLedgerState Block`
  - `LedgerConfig Block`
  - `TopLevelConfig Block`
  - hard-fork era history / interpreter surface
  - `EpochInfo` derived from the era history
- `loadLedgerConfig :: LedgerConfigPaths -> IO LedgerConfigBundle`

The exact field names may adjust to the imported consensus types, but
the exported semantics above must remain visible and tested.

The implementation should use the node config plus Byron/Shelley/Alonzo/
Conway genesis files and mirror the dependency set already proven in
`/code/cardano-utxo-csmt`. It must not open a node socket or query a live
node.

## Slice Plan

### Slice 1: Ledger Config Vertical

Implement the full vertical behavior in one bisect-safe commit:

- Add the `Cardano.StakeCSMT.Ledger.Config` module.
- Add only the needed library/test cabal dependencies.
- Vendor a minimal devnet genesis fixture under `test/fixtures/`.
- Add a unit spec that loads the fixture and asserts the initial ledger
  state and epoch `0` surface.
- Update `test/main.hs` to include the new spec.
- Run `./gate.sh` before committing.

This is one slice because the cabal dependency changes, module, fixture,
and test are mutually dependent. A dependency-only commit would not prove
the feature; a test-only commit cannot compile without the module.

## Owned Files

- `cardano-stake-csmt.cabal`
- `lib/Cardano/StakeCSMT/Ledger/Config.hs`
- `test/Cardano/StakeCSMT/Ledger/ConfigSpec.hs`
- `test/main.hs`
- `test/fixtures/devnet-genesis/node-config.json`
- `test/fixtures/devnet-genesis/byron-genesis.json`
- `test/fixtures/devnet-genesis/shelley-genesis.json`
- `test/fixtures/devnet-genesis/alonzo-genesis.json`
- `test/fixtures/devnet-genesis/conway-genesis.json`

## Forbidden Scope

- Do not modify `application/`, `http/`, `executables/`, or `e2e-test/`.
- Do not add chain-sync, LSQ, node socket, replay, snapshot, CSMT,
  RocksDB, or HTTP behavior.
- Do not change Nix pins, flake lock, CI workflows, release metadata, or
  unrelated specs.

## Verification

- Focused RED: `nix develop --quiet -c just unit "Ledger.Config"`
- Focused GREEN: `nix develop --quiet -c just unit "Ledger.Config"`
- Full gate before commit: `./gate.sh`
- Final ticket gate before ready: `nix develop -c just ci`
