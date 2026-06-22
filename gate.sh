#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

git diff --check

nix develop --quiet -c just ci
nix build --quiet .#default .#e2e-tests

nix develop github:paolino/dev-assets?dir=mkdocs --quiet \
    -c mkdocs build --strict --site-dir site

if nix eval --raw .#packages.x86_64-linux.linux-dev-release-artifacts.name >/dev/null 2>&1; then
    artifact_version="$(
        scripts/release/get-cabal-version
    )-$(git rev-parse --short=7 HEAD)"
    nix build --quiet .#linux-dev-release-artifacts
    artifact_dir="$(readlink -f result)"
    nix run --quiet .#linux-artifact-smoke -- \
        --artifacts-dir "$artifact_dir" \
        --artifact-version "$artifact_version"
fi
