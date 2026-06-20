# Implementation Plan: Repository Scaffold

## Component Map

The scaffold establishes this shared surface for children #3-#11:

| Cabal component | Source directory | Purpose |
| --- | --- | --- |
| main `library` | none / thin wrapper | haskell.nix-compatible main library depending on `cardano-stake-csmt:library` |
| `library library` | `lib/` | pure/domain-facing foundation modules |
| `library http` | `http/` | health/readiness HTTP API and server stub |
| `library application` | `application/` | executable wiring and runtime config |
| `executable cardano-stake-csmt` | `executables/cardano-stake-csmt/` | service entrypoint |
| `test-suite unit-tests` | `test/` | Hspec unit tests |
| `test-suite e2e-tests` | `e2e-test/` | scaffold-level executable/e2e smoke tests |

Namespace root: `Cardano.StakeCSMT.*`.

Initial modules are intentionally narrow:

- `Cardano.StakeCSMT.Application.Health`
- `Cardano.StakeCSMT.HTTP.API`
- `Cardano.StakeCSMT.HTTP.Server`
- `Cardano.StakeCSMT.Application.Run.Config`
- `Cardano.StakeCSMT.Application.Run.Main`

Future tickets add the ledger, CSMT, storage, history, rollback, and
proof modules inside this namespace.

## Slices

### Slice 1 - Haskell and Nix scaffold

Create the buildable package and development tooling in one bisect-safe
commit. This includes:

- `cardano-stake-csmt.cabal`, `cabal.project`, `flake.nix`,
  `nix/project.nix`, `nix/shell.nix`
- minimal Haskell modules under `lib/`, `http/`, `application/`,
  `executables/`, `test/`, and `e2e-test/`
- `justfile`, `fourmolu.yaml`, `.hlint.yaml`, `LICENSE`

The slice must run `./gate.sh`, proving `nix develop --quiet -c just ci`
passes after the scaffold exists.

### Slice 2 - Docs, Speckit, and CI

Add repository-level process surfaces and real CI:

- `mkdocs.yml`, `docs/` skeleton, `.github/workflows/ci.yml`, and
  `.github/workflows/deploy-docs.yml`
- `.specify/` initialized by
  `nix run /code/spec-kit -- init --here --ai claude --script sh --offline --ignore-agent-tools`
- remove generated per-project `.claude/commands/speckit.*.md` and
  `.claude/skills/speckit-*`
- fill `.specify/memory/constitution.md`

The CI workflow must use `runs-on: nixos`, `cachix/cachix-action@v17`
with cache name `paolino`, and expose job names `Build Gate`,
`CI build`, `CI format`, `CI hlint`, and `Docs build`.

### Finalization

After Slice 2 lands and is pushed:

- update the GitHub `main` ruleset required checks from only
  `Build Gate` to the real job names above
- update the PR body with the final component/namespace map and
  verification evidence
- run the final gate at PR head
- drop `gate.sh` only when the PR is ready for review

## Risks

- `ghc9123` can expose tool-version bounds if fourmolu/hlint/cabal are
  pinned. The Nix shell must use unpinned haskell.nix tools.
- CI job names are branch-protection API surface. They must be stable and
  match the required-check contexts exactly.
- Spec Kit init writes agent command copies by default; only `.specify/`
  should remain tracked.
