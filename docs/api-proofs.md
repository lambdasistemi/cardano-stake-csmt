# API and proofs

The HTTP API exposes proof material as JSON plus base16-encoded binary
values. Credentials, coins, epochs, roots, signatures, and proof bytes
use the stable codecs defined by the service modules, so clients should
decode and verify with the same ledger-CBOR and CSMT rules.

## Endpoints

| Method | Path | Response |
| --- | --- | --- |
| `GET` | `/proof/{credential}` | Latest persisted `StakeProofResponse`. |
| `GET` | `/proof/{epoch}/{credential}` | Historical `StakeProofResponse`. |
| `GET` | `/roots` | Array of `StakeRootResponse`, ordered by epoch. |
| `GET` | `/latest-header` | Signed `LatestHeaderResponse`. |
| `GET` | `/history-root` | Current `HistoryRootResponse`. |
| `GET` | `/ready` | `ReadyResponse`. |
| `GET` | `/metrics` | `MetricsResponse`. |
| `GET` | `/health` | Plain-text health check. |

`credential` path segments are base16 ledger-CBOR staking credentials.
Invalid credential text returns `400`. Missing proofs or roots return
`404`. A runtime without query databases returns `503` for proof/root
queries.

When the docs server is enabled, Swagger UI is served at `/swagger-ui`
and the OpenAPI document is served at `/swagger.json`.

## Proof response

`GET /proof/{credential}` chooses the newest persisted epoch root.
`GET /proof/{epoch}/{credential}` fixes the epoch explicitly.

```json
{
  "epoch": 42,
  "credential": "base16-ledger-cbor-credential",
  "stake": 60000000,
  "stakeRoot": "base16-csmt-root",
  "totalStake": 1234567890,
  "proofBytes": "base16-csmt-inclusion-proof"
}
```

Fields:

| Field | Meaning |
| --- | --- |
| `epoch` | Epoch number for the snapshot. |
| `credential` | Base16 ledger-CBOR staking credential used as the CSMT key. |
| `stake` | Active stake for the credential in lovelace. |
| `stakeRoot` | CSMT root for the epoch snapshot. |
| `totalStake` | Sum of all credential stake in the epoch snapshot. |
| `proofBytes` | Base16-encoded CSMT inclusion proof. |

To verify this branch, decode `proofBytes`, check that the proof key is
the credential key, check that the proof value is the hash of the
ledger-CBOR `Coin`, and verify the inclusion proof against `stakeRoot`.

## Root responses

`GET /roots` returns the epoch roots persisted by the stake database:

```json
[
  {
    "epoch": 42,
    "stakeRoot": "base16-csmt-root",
    "totalStake": 1234567890
  }
]
```

`GET /history-root` returns the current root of the history accumulator:

```json
{
  "historyRoot": "base16-history-root"
}
```

Each history leaf is keyed by epoch and hashes the encoded epoch-root
record. That leaf commits to the epoch, the stake root, and
`totalStake`; clients should treat those three values as one unit.

## Latest signed header

`GET /latest-header` returns the newest persisted root signed by the
configured Ed25519 key:

```json
{
  "epoch": 42,
  "stakeRoot": "base16-csmt-root",
  "totalStake": 1234567890,
  "signature": "base16-ed25519-signature",
  "publicKey": "base16-ed25519-public-key"
}
```

The signed payload is the concatenation of:

```text
ledger-cbor(epoch) || csmt-hash(stakeRoot) || ledger-cbor(totalStake)
```

Production clients should verify the signature with an expected pinned
public key. The embedded `publicKey` is useful for discovery and local
checks, but by itself it does not authenticate the service identity.

## Two-level verification

A complete historical voting proof has two CSMT branches:

1. A credential branch proves `(credential, stake)` under the epoch
   `stakeRoot`.
2. A history branch proves `(epoch, stakeRoot, totalStake)` under
   `historyRoot`.

The HTTP proof endpoint returns the credential branch. The history
accumulator uses the same CSMT proof semantics for the epoch-root branch,
with the epoch as the key and the encoded epoch-root record as the
value. Verifiers that receive a full historical proof bundle should:

1. Verify the epoch-root branch against the published `historyRoot`.
2. Verify the credential branch against the proven `stakeRoot`.
3. Check that the response `epoch`, `stakeRoot`, and `totalStake` match
   the proven history leaf.
4. Use `stake / totalStake` for voting weight, quorum, or threshold
   calculations.

Latest-epoch flows can use the signed latest header as the trusted
anchor instead of a history branch. The same denominator rule applies:
the `totalStake` used for threshold checks must be the value committed
by the signed header or history leaf that also commits to `stakeRoot`.

## Operational responses

Readiness:

```json
{
  "ready": true
}
```

Metrics:

```json
{
  "ready": true,
  "latestEpoch": null
}
```

`latestEpoch` is nullable so the endpoint remains valid before any epoch
root has been persisted.
