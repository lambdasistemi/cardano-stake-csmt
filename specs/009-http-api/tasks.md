# Tasks: HTTP API And Proofs

## Slice 1 - Servant API Types And Wire Codecs

- [x] T001-S1 Add `Cardano.StakeCSMT.HTTP.Base16` and replace the scaffold route model with servant API types in `Cardano.StakeCSMT.HTTP.API`.
- [x] T002-S1 Add JSON and Swagger schema instances for proof, root, history-root, ready, metrics, and latest-header response types.
- [x] T003-S1 Add credential/base16/hash/proof rendering helpers using the existing CSMT and ledger codecs.
- [x] T004-S1 Register servant/swagger/base16 dependencies, modules, and focused API/codecs tests in `cardano-stake-csmt.cabal` and `test/main.hs`.
- [x] T005-S1 Run the focused HTTP API/codecs test and `./gate.sh`, then commit as `feat(http): define stake proof API`.

## Slice 2 - Query Layer And Proof Handlers

- [x] T006-S2 Add `Cardano.StakeCSMT.HTTP.Query` functions for historical proof, latest proof, epoch roots, and history root using only #6/#7 public APIs and typed KV cursor iteration.
- [x] T007-S2 Replace scaffold WAI routing with servant handlers in `Cardano.StakeCSMT.HTTP.Server`, preserving dependency injection for tests.
- [x] T008-S2 Add tests proving proof bytes verify with `CSMT.Hashes.verifyInclusionProof`, latest proof chooses the newest epoch, invalid credential returns 400, and missing root/proof returns 404.
- [x] T009-S2 Run the focused HTTP server/query test and `./gate.sh`, then commit as `feat(http): serve stake proof queries`.

## Slice 3 - Swagger, Readiness, Metrics, And Application Wiring

- [x] T010-S3 Add `Cardano.StakeCSMT.HTTP.Swagger` and Swagger UI/docs application support.
- [x] T011-S3 Add JSON `/ready` and `/metrics` responses and CORS-enabled API/docs WAI applications.
- [x] T012-S3 Wire `Application.Run.Config` and `Application.Run.Main` to run the HTTP API/docs servers with query actions.
- [x] T013-S3 Add focused tests for swagger JSON, ready/metrics responses, and application wiring.
- [x] T014-S3 Run the focused HTTP swagger/wiring test and `./gate.sh`, then commit as `feat(http): wire docs and service status`.

## Slice 4 - Signed Latest Header

- [x] T015-S4 Add `Cardano.StakeCSMT.HTTP.Signing` with deterministic latest-header payload bytes and Ed25519 sign/verify helpers.
- [x] T016-S4 Include the signed latest header in latest proof responses or an adjacent latest-header response shape, with public key and signature bytes in base16.
- [x] T017-S4 Add tests proving the signature verifies for the exact `(epoch, stakeRoot, totalStake)` payload and fails when any field changes.
- [x] T018-S4 Run the focused HTTP signing test and `./gate.sh`, then commit as `feat(http): sign latest stake root header`.

## Finalization

- [ ] T019-F Run `nix develop -c just ci` at HEAD.
- [ ] T020-F Update PR body with delivered behavior and verification evidence.
- [ ] T021-F Drop `gate.sh` in `chore: drop gate.sh (ready for review)` and mark the PR ready.
