# Tasks: Live HTTP E2E

## Slice 1 - Live HTTP Proof

- [X] T001-S1 Add `Cardano.StakeCSMT.E2E.LiveHTTPSpec` that starts
  `withCardanoNode "e2e-test/genesis"`, launches the daemon on an ephemeral
  localhost port with network magic `42`, a temporary store, and a deterministic
  signing key, then shuts it down cleanly.
- [X] T002-S1 Poll `GET /ready` until `ReadyResponse{ready = True}` with a
  bounded timeout suitable for the devnet epoch transition.
- [X] T003-S1 Query `GET /proof/<e2e genesis staking credential>` and assert
  the returned stake is `Coin 30_000_000_000_000_000`.
- [X] T004-S1 Query `GET /roots`, decode the returned epoch root matching the
  proof epoch, decode the proof bytes, and verify the inclusion proof with
  `verifyCredentialProof` off the wire.
- [X] T005-S1 Query `GET /history-root` and assert it is non-empty after
  readiness and consistent with available roots.
- [X] T006-S1 Query `GET /latest-header`, verify the response signature with
  the existing HTTP signing verifier, and assert it matches the latest root
  observed from `/roots`.
- [X] T007-S1 Register the new e2e module in `e2e-test/main.hs` and
  `cardano-stake-csmt.cabal`, adding only e2e-suite test dependencies needed
  for HTTP/process/port handling.
- [X] T008-S1 Apply the A-001-authorized root-cause fix for the live daemon
  `PastHorizon` failure in the minimal replay/indexer epoch-resolution module:
  derive the observed epoch from current replay/ledger state instead of a stale
  horizon lookup, and do not catch or swallow `PastHorizon`.
- [X] T009-S1 Add threaded RTS wiring to the `cardano-stake-csmt` executable
  and `e2e-tests` suite (`-threaded`, `-rtsopts`, `-with-rtsopts=-N`) because
  both run forked/network daemon code.
- [X] T010-S1 Run `nix develop --quiet -c just e2e` and `./gate.sh`, then
  commit as `fix(replay): derive epoch from ticked ledger state`.

## Finalization

- [ ] T011-F Run `just ci` at HEAD.
- [ ] T012-F Run `nix build .#default .#e2e-tests` at HEAD.
- [ ] T013-F Update PR #32 body with delivered behavior and verification
  evidence, including `Closes #26`.
- [ ] T014-F Drop `gate.sh` in `chore: drop gate.sh (ready for review)`, push,
  mark the PR ready, and report COMPLETE with PR URL and head SHA.
