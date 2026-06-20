# shellcheck shell=bash

set unstable := true

default:
    @just --list

build:
    #!/usr/bin/env bash
    set -euo pipefail
    cabal build all --enable-tests -O0

unit match="" *args='':
    #!/usr/bin/env bash
    set -euo pipefail
    # shellcheck disable=SC2050
    if [[ '{{ match }}' == "" ]]; then
        cabal test unit-tests -O0 \
            --test-show-details=direct \
            --test-options="{{ args }}"
    else
        cabal test unit-tests -O0 \
            --test-show-details=direct \
            --test-option=--match \
            --test-option="{{ match }}" \
            --test-options="{{ args }}"
    fi

e2e:
    #!/usr/bin/env bash
    set -euo pipefail
    cabal test e2e-tests -O0 --test-show-details=direct

format:
    #!/usr/bin/env bash
    set -euo pipefail
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -i {} +
    nixfmt flake.nix nix/*.nix

format-check:
    #!/usr/bin/env bash
    set -euo pipefail
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec fourmolu -m check {} +
    nixfmt -c flake.nix nix/*.nix

hlint:
    #!/usr/bin/env bash
    set -euo pipefail
    find . -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec hlint {} +

ci:
    #!/usr/bin/env bash
    set -euo pipefail
    just build
    just unit
    just e2e
    just format-check
    just hlint
