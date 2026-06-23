# Tasks: Live HTTP E2E

## Slice 1 - Live HTTP Proof

- [ ] T001-S1 Add `Cardano.StakeCSMT.E2E.LiveHTTPSpec` that starts
  `withCardanoNode "e2e-test/genesis"`, launches the daemon on an ephemeral
  localhost port with network magic `42`, a temporary store, and a deterministic
  signing key, then shuts it down cleanly.
- [ ] T002-S1 Poll `GET /ready` until `ReadyResponse{ready = True}` with a
  bounded timeout suitable for the devnet epoch transition.
- [ ] T003-S1 Query `GET /proof/<e2e genesis staking credential>` and assert
  the returned stake is `Coin 30_000_000_000_000_000`.
- [ ] T004-S1 Query `GET /roots`, decode the returned epoch root matching the
  proof epoch, decode the proof bytes, and verify the inclusion proof with
  `verifyCredentialProof` off the wire.
- [ ] T005-S1 Query `GET /history-root` and assert it is non-empty after
  readiness and consistent with available roots.
- [ ] T006-S1 Query `GET /latest-header`, verify the response signature with
  the existing HTTP signing verifier, and assert it matches the latest root
  observed from `/roots`.
- [ ] T007-S1 Register the new e2e module in `e2e-test/main.hs` and
  `cardano-stake-csmt.cabal`, adding only e2e-suite test dependencies needed
  for HTTP/process/port handling.
- [ ] T008-S1 Run `nix develop --quiet -c just e2e` and `./gate.sh`, then
  commit as `test(e2e): prove live HTTP daemon proof path`.

## Finalization

- [ ] T009-F Run `just ci` at HEAD.
- [ ] T010-F Run `nix build .#default .#e2e-tests` at HEAD.
- [ ] T011-F Update PR #32 body with delivered behavior and verification
  evidence, including `Closes #26`.
- [ ] T012-F Drop `gate.sh` in `chore: drop gate.sh (ready for review)`, push,
  mark the PR ready, and report COMPLETE with PR URL and head SHA.
