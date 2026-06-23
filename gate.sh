#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix build .#packages.x86_64-linux.e2e-tests
