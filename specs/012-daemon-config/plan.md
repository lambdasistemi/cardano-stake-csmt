# Implementation Plan: Daemon Config Surface

## Existing Context

`Cardano.StakeCSMT.Application.Run.Config` currently accepts only
`CARDANO_STAKE_CSMT_API_PORT` and builds a mostly empty `RuntimeConfig`.
`Run.Main` falls back to unavailable HTTP handlers when stake/history DB
paths are absent. Epic #27 changes that posture: a daemon launch without
the required socket/network/ledger/db inputs must fail closed.

The ledger and replay layers already have the downstream shapes this
ticket must prepare for:

- `Cardano.StakeCSMT.Ledger.Config.ledgerConfigPathsFromDirectory`
  expects a directory containing `node-config.json` and genesis files.
- `Cardano.StakeCSMT.Ledger.Replay.ReplayFollowerConfig` consumes a
  socket path, network magic, and Byron epoch slots.
- `Run.Main.runtimeHandlers` already accepts stake/history database
  paths and an optional Ed25519 signing key.

## Public API Shape

The implementation should keep field names stable and explicit:

- `configNodeSocketPath :: FilePath`
- `configNetworkMagic :: Word32`
- `configByronEpochSlots :: Word64`
- `configLedgerConfigDir :: FilePath`
- `configStakeDbPath :: FilePath`
- `configHistoryDbPath :: FilePath`
- `configCheckpointDir :: Maybe FilePath`
- `configSigningKeyPath :: Maybe FilePath`
- `configSigningKey :: Maybe (SignKeyDSIGN Ed25519DSIGN)`
- `configPort :: Int`
- `configDocsPort :: Maybe Int`

Use a documented default of `21_600` for Byron epoch slots when neither
CLI nor env provides one. API port may keep its existing `8080` default.
Docs port and checkpoint directory remain optional.

Add a parser module, expected name:

```haskell
Cardano.StakeCSMT.Application.Run.CLI
```

Suggested surface:

```haskell
runtimeConfigFromCommandLine :: IO RuntimeConfig
runtimeConfigFromArguments
    :: [String] -> [(String, String)] -> IO (Either String RuntimeConfig)
```

The exact names may change if the local style points to clearer names,
but tests must be able to exercise argv/env parsing without mutating the
process environment.

## Environment Fallbacks

Preserve `CARDANO_STAKE_CSMT_API_PORT`. Use consistent names for the new
fallbacks:

- `CARDANO_STAKE_CSMT_NODE_SOCKET`
- `CARDANO_STAKE_CSMT_NETWORK_MAGIC`
- `CARDANO_STAKE_CSMT_BYRON_EPOCH_SLOTS`
- `CARDANO_STAKE_CSMT_LEDGER_CONFIG_DIR`
- `CARDANO_STAKE_CSMT_STAKE_DB`
- `CARDANO_STAKE_CSMT_HISTORY_DB`
- `CARDANO_STAKE_CSMT_CHECKPOINT_DIR`
- `CARDANO_STAKE_CSMT_SIGNING_KEY`
- `CARDANO_STAKE_CSMT_DOCS_PORT`

CLI flags take precedence over environment values.

## Validation

Fail closed with messages that name the missing flag/env fallback and,
for invalid files, the offending path.

Required checks:

- node socket: present and `doesFileExist`
- network magic: present and numeric
- ledger config directory: present and `doesDirectoryExist`
- stake DB path: present and non-empty
- history DB path: present and non-empty

Signing key loading should use the existing `cardano-crypto-class`
Ed25519 raw key serialisation/deserialisation API if available. The
tests can write a deterministic generated key to a temp file and assert
that the parsed config contains the same signing key.

## Slice Breakdown

### Slice 1: Runtime CLI Config

Add the runtime config fields, parser module, minimal startup threading,
and focused unit coverage in one vertical commit. This includes the
mechanical Cabal component updates needed to build the new module and
its dependencies.

The slice must not add the indexer loop, change HTTP proof behavior, or
replace the unavailable-handler path with live daemon wiring beyond the
config fail-closed behavior.

## Verification

- Focused command: `nix develop --quiet -c just unit "Application.Run"`
- Full gate: `./gate.sh`
- Final required commands before COMPLETE:
  - `just ci`
  - `nix build .#default`
