# Cardano Stake CSMT

Cardano Stake CSMT is a Haskell service scaffold for publishing stake distribution roots and proofs in a compact sparse Merkle tree format.

The repository currently contains the project skeleton, health and readiness endpoints, unit and end-to-end smoke tests, Nix development tooling, and CI wiring. Ledger extraction, CSMT construction, proof generation, and persistence are planned work and are not implemented in this scaffold.

## Current scope

- Cabal package with library, executable, HTTP, unit test, and e2e test components.
- Nix flake with a development shell and package outputs for the service and tests.
- `just` recipes for build, unit, e2e, formatting, HLint, and CI.
- Documentation and Spec Kit project structure for the implementation plan.

## Repository layout

- `lib/`: pure library namespace for stake CSMT modules.
- `http/`: HTTP health and readiness surface.
- `executables/`: service executable entry point.
- `test/` and `e2e-test/`: scaffold-level test suites.
- `nix/`: Haskell.nix project and shell definitions.
- `docs/`: MkDocs documentation.
- `.specify/`: Spec Kit templates, scripts, and project constitution.
