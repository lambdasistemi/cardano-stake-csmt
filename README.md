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

## Install Artifacts

Release tags publish Linux AppImage, DEB, RPM, and `SHA256SUMS`
artifacts built from the flake. Pull requests build the same artifact
shape with a development version suffix and smoke-test each package by
starting the service locally and probing `/ready` plus `/health`.

The Darwin release workflow builds a Homebrew tarball and formula for
`lambdasistemi/homebrew-tap`. Pull requests use the shared local tap
test path only; tag workflows publish the GitHub release asset and tap
formula after Cabal, changelog, and tag consistency checks.

## Release Process

`cardano-stake-csmt.cabal` is the version source of truth. The release
planner opens or updates `release/cabal-release` with the next Cabal
version and generated `CHANGELOG.md` notes. After that PR merges, the
next main-branch planner run creates `v<version>` when the Cabal file
and changelog already match.

Planner branch and tag pushes are made with a scoped token minted from
the org `lambdasistemi-ci` GitHub App (`CI_APP_ID` variable +
`CI_APP_PRIVATE_KEY` secret), so no per-repo deploy key is required.
Darwin/Homebrew publication still needs `TAP_TOKEN`;
`CACHIX_AUTH_TOKEN` lets macOS release builds populate the shared cache.

## License

Apache-2.0
