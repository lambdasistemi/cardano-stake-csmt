# Feature Specification: Ledger Config

**Feature Branch**: `feat/ledger-config`
**Issue**: #3
**Created**: 2026-06-20
**Status**: Draft

## P1 User Story

As the stake CSMT service, I can load a Cardano node configuration and
its Byron, Shelley, Alonzo, and Conway genesis files and obtain the
genesis ledger surface needed by later replay work: `ProtocolInfo IO
Block`, genesis `ExtLedgerState`, `LedgerConfig` / `TopLevelConfig`, and
`EpochInfo` / era history.

## Acceptance Criteria

- `Cardano.StakeCSMT.Ledger.Config` builds `ProtocolInfo IO Block` for
  the Cardano hard-fork block from local node config plus genesis files.
- The module exposes the initial `ExtLedgerState`, ledger configuration,
  top-level consensus configuration, hard-fork era history, and
  `EpochInfo`.
- A unit test loads a vendored devnet genesis fixture and asserts that
  the genesis ledger state and epoch information are usable.
- The implementation does not use LocalStateQuery, chain sync, block
  replay, snapshot extraction, CSMT construction, or HTTP/application
  wiring.

## Functional Requirements

- **FR-001**: Provide a small input type that names the node config and
  genesis directory or individual genesis files needed to construct the
  Cardano consensus protocol info.
- **FR-002**: Build `ProtocolInfo IO Block`, where `Block` is the
  project's Cardano hard-fork block alias (`CardanoBlock StandardCrypto`).
- **FR-003**: Return a structured value containing:
  - `ProtocolInfo IO Block`
  - `ExtLedgerState Block`
  - `LedgerConfig Block`
  - `TopLevelConfig Block`
  - hard-fork era history / interpreter surface
  - `EpochInfo` derived from that era history
- **FR-004**: Decode the same devnet node config and genesis JSON layout
  used by local Cardano fixtures.
- **FR-005**: Add only the Cardano consensus/ledger dependencies needed
  by the public `library` component and its unit test.
- **FR-006**: Unit coverage must exercise the real fixture path and fail
  if the loader cannot construct the initial ledger state or cannot query
  epoch `0`.

## Non-Goals

- No block application or replay; that belongs to #4.
- No chain-sync, no N2C connection, and no LocalStateQuery.
- No ledger snapshot extraction, CSMT construction, storage, or HTTP
  API behavior.

## References

- `/code/cardano-utxo-csmt/lib/Cardano/UTxOCSMT/Bootstrap/Genesis.hs`
- `/code/cardano-utxo-csmt/application/Cardano/UTxOCSMT/Application/Run/GenesisData.hs`
- `/code/cardano-utxo-csmt/cardano-utxo-csmt.cabal`
- `/code/cardano-utxo-csmt/e2e-test/genesis/`
- `/code/cardano-node-clients/devnet/genesis/`
