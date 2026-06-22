# Getting started

## Prerequisites

Use Nix with flake support enabled. The flake pins the Haskell
toolchain, Cardano dependencies, and development utilities used by the
project.

## Development shell

Enter the project shell:

```sh
nix develop
```

The shell provides Cabal, Fourmolu, HLint, Just, Nixfmt, and
ShellCheck.

## Common checks

Run the local checks through Just:

```sh
just build
just unit
just e2e
just format-check
just hlint
```

Run the complete local CI recipe:

```sh
just ci
```

## Build the executable

Build the Nix package:

```sh
nix build .#cardano-stake-csmt
```

The resulting binary is available under:

```sh
./result/bin/cardano-stake-csmt
```

The default executable starts the API server on port `8080` with the
default runtime configuration. Deployments that serve proofs wire the
runtime with stake and history RocksDB paths and, when signed latest
headers are required, an Ed25519 signing key.

## Build release artifacts

Build Linux development artifacts locally:

```sh
nix build .#linux-dev-release-artifacts
```

The artifact directory contains an AppImage, DEB, RPM, generic
`cardano-stake-csmt.AppImage`, and `SHA256SUMS`. Smoke-test the
artifacts without publishing them:

```sh
artifact_dir="$(readlink -f result)"
artifact_version="$(scripts/release/get-cabal-version)-$(git rev-parse --short=7 HEAD)"
nix run .#linux-artifact-smoke -- --artifacts-dir "$artifact_dir" --artifact-version "$artifact_version"
```

On macOS, the Darwin workflow builds `.#darwin-dev-homebrew-artifacts`
through the shared Homebrew release action. Pull requests use local
tarball and tap checks only; tag workflows publish after Cabal,
changelog, and tag consistency checks.

## Plan a release

The Cabal file owns the project version:

```sh
scripts/release/get-cabal-version
scripts/release/check-version-consistency
```

Preview the release planner without creating branches or tags:

```sh
RELEASE_PLAN_DRY_RUN=1 scripts/release/plan
```

The non-dry-run planner is intended for the `Release Planner` workflow
on `main`. It creates or updates `release/cabal-release` with the next
Cabal version and changelog notes, or creates `v<version>` after the
Cabal version and changelog already match. Operators must configure
`RELEASE_BOT_SSH_KEY`; Darwin/Homebrew publication also needs
`TAP_TOKEN`, and `CACHIX_AUTH_TOKEN` enables cache pushes from release
builds.

## Documentation

Build the documentation with the shared MkDocs environment:

```sh
nix develop github:paolino/dev-assets?dir=mkdocs --quiet -c mkdocs build --strict --site-dir site
```

Serve the documentation locally while editing:

```sh
nix develop github:paolino/dev-assets?dir=mkdocs --quiet -c mkdocs serve
```

The CI Pages workflow runs the same strict MkDocs build for pull
requests. It uploads and deploys the Pages artifact only when the
workflow is running on `main`.

## Query the API

With an API deployment available, use base16 ledger-CBOR staking
credentials in proof URLs:

```sh
curl http://127.0.0.1:8080/ready
curl http://127.0.0.1:8080/roots
curl http://127.0.0.1:8080/latest-header
curl http://127.0.0.1:8080/proof/<credential>
curl http://127.0.0.1:8080/proof/<epoch>/<credential>
curl http://127.0.0.1:8080/history-root
```

When the runtime enables the docs server, Swagger UI is served from
`/swagger-ui` and the OpenAPI document from `/swagger.json` on the docs
port.
