#!/usr/bin/env bash
set -euo pipefail

git diff --check
nix develop -c just ci
