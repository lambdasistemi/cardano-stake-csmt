# Architecture

Cardano Stake CSMT separates deterministic ledger/tree logic from the
runtime boundary that follows a node, persists roots, and serves HTTP
proofs. The service maintains Cardano ledger state by replaying blocks
from Origin, extracts epoch-boundary stake snapshots, commits those
snapshots to per-epoch CSMTs, and accumulates epoch roots into a history
tree.

## Boundary model

The pure core modules define:

- extraction of stake snapshots from `ExtLedgerState`;
- per-epoch CSMT root construction and credential inclusion proofs;
- history tree construction over epoch-root leaves;
- stable CBOR and ledger-CBOR codecs for credentials, coins, epochs,
  roots, and proofs.

The runtime shell owns:

- node-to-client ChainSync connection to the local Cardano node;
- trusted block application and rollback handling;
- RocksDB-backed stake and history databases;
- HTTP, Swagger, readiness, metrics, and optional latest-header signing.

## Replay source

The production replay path starts ChainSync from Origin over the
node-to-client protocol. It does not query stake distribution through
Local State Query. This is important for verifiability: every published
stake root is derived from the same trusted block stream and consensus
ledger transition rules that a local node uses.

The replay worker starts from the genesis `ExtLedgerState` in the loaded
ledger configuration. For each fetched block it applies the trusted
ledger reapply path (`tickThenReapply`) and then applies the returned
table diffs to obtain the next `ExtLedgerState`.

## Epoch snapshots

The stake snapshot extractor reads the Shelley-based ledger state inside
`ExtLedgerState`. Byron has no stake snapshot and is rejected by the
extractor. For Shelley and later eras, the service projects:

```text
esSnapshots . ssStakeMark . ssActiveStake
```

to a map of staking credential to active stake. The total stake stored
with the root is the sum of the projected credential stakes.

Epoch transitions are observed during replay by comparing the epoch at
the applied block slot with the replay state's last observed epoch. The
boundary event is the point at which the completed snapshot is eligible
to become an epoch CSMT.

## Per-epoch CSMTs

Each epoch snapshot is stored under an epoch namespace. The CSMT key is
the ledger-CBOR staking credential and the CSMT value is the ledger-CBOR
`Coin` amount hashed into the tree value. The resulting root record is:

```text
EpochRoot {
  epochRootHash,
  epochRootTotalStake
}
```

The root record is persisted by epoch. Credential proofs are inclusion
proofs against this root and are valid only for the exact credential,
stake amount, and epoch root they were built from.

## History tree

Every completed epoch root is inserted into a second CSMT: the history
accumulator. Its leaf key is the ledger-CBOR epoch number. Its leaf
value is the hash of the encoded epoch-root record, so the history leaf
commits to:

```text
(epoch, stakeRoot, totalStake)
```

Including `totalStake` in the history leaf prevents a verifier from
mixing a valid stake root with a different voting denominator. The
current history root is stored separately and exposed through HTTP.

## Rollback recovery

ChainSync rollback is handled at the replay layer. The checkpoint-aware
follower stores replay checkpoints on a configured slot cadence and
keeps a bounded tail of recently fetched blocks. On rollback:

1. Normalize the rollback point to a checkpoint point.
2. Select the nearest stored checkpoint at or before the target.
3. Load the replay state saved for that checkpoint.
4. Recover the retained tail segment from the checkpoint to the target.
5. Replay that tail into the loaded state.
6. Truncate the retained tail after the rollback target and resume
   following the node.

If no usable checkpoint plus tail segment can recover the target, the
follower resets its ChainSync intersection instead of pretending the
local state is valid.

## HTTP surface

The API serves the committed data:

| Endpoint | Purpose |
| --- | --- |
| `GET /proof/{credential}` | Latest persisted credential stake proof. |
| `GET /proof/{epoch}/{credential}` | Historical credential stake proof. |
| `GET /roots` | Ordered epoch root records with `totalStake`. |
| `GET /latest-header` | Signed latest `(epoch, stakeRoot, totalStake)`. |
| `GET /history-root` | Current root of the epoch-root history tree. |
| `GET /ready` | Readiness JSON for orchestration. |
| `GET /metrics` | Minimal metrics JSON. |
| `GET /health` | Plain-text health check. |

When the docs application is enabled, Swagger UI is available at
`/swagger-ui` and the OpenAPI document at `/swagger.json`.

## Voting verification

A voting client verifies a stake proof off-chain before accepting the
stake amount as voting power:

1. Choose the trusted root. For latest voting rounds, verify
   `/latest-header` with the pinned service public key and use its
   signed `epoch`, `stakeRoot`, and `totalStake`. For historical rounds,
   verify the epoch-root leaf `(epoch, stakeRoot, totalStake)` against
   the published history root.
2. Verify the credential inclusion proof against `stakeRoot`, using the
   ledger-CBOR credential as the proof key and the ledger-CBOR `Coin` as
   the proof value.
3. Use `stake` as the numerator and `totalStake` as the denominator for
   quorum or threshold checks.

The denominator is part of both the signed latest header and the history
leaf. A verifier should reject any proof bundle that verifies the stake
branch but supplies `totalStake` from a different root record.
