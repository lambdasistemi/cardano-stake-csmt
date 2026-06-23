#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix develop --quiet -c just unit "Indexer"
nix develop --quiet -c just format-check
nix develop --quiet -c just hlint
