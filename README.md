# Cardano Stake CSMT

An HTTP service that maintains a Compact Sparse Merkle Tree (CSMT) over
Cardano's per-epoch stake distribution, enabling verifiable
stake-weighted voting proofs.

It syncs the chain from genesis over the node-to-client protocol,
maintains the consensus ledger state, and at each epoch boundary commits
the credential-level stake snapshot (`credential → stake`) into a CSMT.
Each finalized epoch root is accumulated into a history root, so the
service exposes both the latest stakes and a Merkle tree of all past
stakes. Inclusion proofs verify off-chain and on-chain (via `aiken-csmt`).

Sibling project: [cardano-utxo-csmt](https://github.com/lambdasistemi/cardano-utxo-csmt).

## Features

- **Genesis Sync**: replays the chain via node-to-client, maintaining ledger state
- **Per-epoch Snapshots**: credential-level stake distribution, Byron through Conway
- **Merkle Proofs**: inclusion proofs of voting power for any credential at any epoch
- **History Root**: an accumulator committing every past epoch's stake root
- **REST API**: HTTP interface with Swagger documentation

## Development

```bash
nix develop      # enter the dev shell
just ci          # build + test + format-check + hlint
```

## License

Apache-2.0
