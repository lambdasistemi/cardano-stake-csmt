# Feature Specification: Replay Engine

## P1 User Story

As the stake CSMT service, I need to stream full Cardano blocks from
node-to-client ChainSync starting at Origin, reapply each trusted block
into the consensus `ExtLedgerState`, and be notified once when the
replayed chain crosses into a new epoch.

## Scope

- Add `Cardano.StakeCSMT.Ledger.Replay` to the public `library`.
- Reuse `Cardano.StakeCSMT.Ledger.Config` from issue #3 for the
  `TopLevelConfig`, genesis `ExtLedgerState`, era history, and epoch
  lookup.
- Apply blocks with consensus `tickThenReapply`, not full validation.
- Preserve ledger-table values after each reapply by applying the
  returned diff to the previous state.
- Wire a node-to-client ChainSync follower that receives full blocks and
  threads the replay state through `ChainFollower.Follower`.
- Fire the epoch callback only when the observed epoch changes, and only
  once for each observed transition.

## Functional Requirements

- FR1: `Replay` exposes a pure replay state wrapper containing the
  current `ExtLedgerState StakeBlock ValuesMK` and the last observed
  epoch.
- FR2: `Replay` exposes a block replay function that takes a
  `LedgerConfigBundle`, an epoch-transition callback, the current replay
  state, and one `StakeBlock`, then returns the next replay state.
- FR3: The block replay function calls
  `Ouroboros.Consensus.Ledger.Abstract.tickThenReapply` with
  `OmitLedgerEvents` and `ExtLedgerCfg ledgerConfigTopLevelConfig`.
- FR4: The block replay function updates ledger table values with
  `Ouroboros.Consensus.Ledger.Tables.Utils.applyDiffs`.
- FR5: Epoch detection uses the bundle's epoch lookup for the replayed
  block slot; the callback receives previous epoch, new epoch, and block
  slot.
- FR6: The ChainSync follower starts from Origin and converts N2C
  `Fetched` values into replay-state transitions without LSQ.
- FR7: Rollback persistence is not implemented in this ticket. A
  rollback from the N2C follower may reset to Origin/genesis or surface
  an explicit unsupported rollback error, but it must not invent durable
  history.
- FR8: Tests prove callback de-duplication and replay-state threading
  without relying on snapshot extraction, CSMT construction, HTTP, or
  rollback persistence.
- FR9: An e2e proof replays a devnet chain to tip without error.

## Success Criteria

- The library exposes `Cardano.StakeCSMT.Ledger.Replay`.
- Unit tests cover epoch callback behavior and state threading.
- The N2C follower path is wired through `Cardano.Node.Client.N2C.ChainSync`
  or an equivalent existing full-block N2C client pattern.
- `nix develop -c just ci` passes locally.

## Non-Goals

- No stake snapshot extraction.
- No CSMT construction or root/proof generation.
- No history database.
- No rollback persistence.
- No HTTP/API changes.
