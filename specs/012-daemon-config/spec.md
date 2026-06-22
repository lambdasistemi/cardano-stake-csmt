# Feature Specification: Daemon Config Surface

**Feature Branch**: `feat/23-daemon-config`
**Issue**: #23
**Parent Epic**: #27
**Created**: 2026-06-22
**Status**: Draft

## P1 User Story

As an operator, I can launch `cardano-stake-csmt` with explicit daemon
configuration for the node socket, network, ledger config directory,
stake database, history database, and optional service ports/checkpoint
and signing-key paths, and the process fails closed with an actionable
error when required runtime inputs are missing or invalid.

## Acceptance Criteria

- `RuntimeConfig` carries stable fields for node socket path, network
  magic, Byron epoch slots, ledger-config directory, stake-db path,
  history-db path, checkpoint directory, signing-key path/key, API port,
  and optional docs port.
- A CLI parser populates `RuntimeConfig`; environment variables remain a
  fallback for sensible values, including the existing API port env var.
- Missing or invalid required values fail closed for node socket,
  network magic, ledger-config directory, stake-db path, and history-db
  path. There are no silent defaults for those values.
- When a signing-key path is provided, the Ed25519 signing key is loaded
  from the file and exposed on `RuntimeConfig`.
- Unit tests cover successful parsing, every required-missing failure,
  invalid required paths/values, and signing-key loading.

## Functional Requirements

- **FR-001**: Add a CLI-facing parser module under
  `Cardano.StakeCSMT.Application.Run.*` that can parse argv plus an
  environment fallback map into `RuntimeConfig`.
- **FR-002**: Support at least these CLI flags:
  `--node-socket`, `--network-magic`, `--byron-epoch-slots`,
  `--ledger-config-dir`, `--stake-db`, `--history-db`,
  `--checkpoint-dir`, `--signing-key`, `--api-port`, and
  `--docs-port`.
- **FR-003**: Preserve `CARDANO_STAKE_CSMT_API_PORT` as the API port
  fallback when `--api-port` is absent.
- **FR-004**: Provide environment fallback names for the new daemon
  paths/values using the `CARDANO_STAKE_CSMT_*` prefix, but do not make
  fallback values silent defaults.
- **FR-005**: Validate required filesystem inputs at config load time:
  the node socket path exists, the ledger config directory exists, and
  database paths are present and non-empty.
- **FR-006**: Validate ports are integers in `1..65535`, network magic
  is numeric, and Byron epoch slots is positive.
- **FR-007**: Load an Ed25519 signing key from `--signing-key` when
  present and fail with the path in the error message when it cannot be
  decoded.
- **FR-008**: Thread the parser into the executable only enough for the
  daemon to use CLI/env config on startup.

## Non-Goals

- No indexer loop or ChainSync startup; that belongs to #24.
- No daemon concurrency or shared handle rewiring beyond the minimal
  startup config thread; that belongs to #25.
- No HTTP API or proof format changes.
- No second GHC toolchain, generic Nix bundler, or unrelated release
  packaging change.

## Success Criteria

- Focused unit tests for application runtime config are green.
- `just ci` is green.
- `nix build .#default` is green.
