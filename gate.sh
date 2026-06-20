#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

git diff --check

if [[ -f flake.nix && -f justfile ]]; then
    nix develop --quiet -c just ci
else
    echo "bootstrap gate: scaffold not present yet"
fi
