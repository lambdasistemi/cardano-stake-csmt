# Changelog for cardano-stake-csmt

## Unreleased

## [0.1.1.0](https://github.com/lambdasistemi/cardano-stake-csmt/compare/v0.1.0.0...v0.1.1.0) (2026-06-24)

### Features

* **app:** add daemon runtime config ([579c3e9](https://github.com/lambdasistemi/cardano-stake-csmt/commit/579c3e9f0c32f10febd9b3798767b7bc72bc2f7e))
* **indexer:** add epoch snapshot writer ([d25c370](https://github.com/lambdasistemi/cardano-stake-csmt/commit/d25c37044e7c6f608b8f5af0ade6516b03634a77))
* **indexer:** replay finalized epoch boundaries ([d164bdf](https://github.com/lambdasistemi/cardano-stake-csmt/commit/d164bdfc3703e397d62e98d2e051a71a05fbd32f))
* **app:** add daemon readiness signal ([d4500ad](https://github.com/lambdasistemi/cardano-stake-csmt/commit/d4500ad3b9ed57f902a7c114f4850aa621da0b28))
* **indexer:** make epoch writes atomic ([fbc8331](https://github.com/lambdasistemi/cardano-stake-csmt/commit/fbc833122757ea96cc27b4a10d63f1e23c2cb036))
* **app:** wire indexer into daemon runtime ([170dae1](https://github.com/lambdasistemi/cardano-stake-csmt/commit/170dae183d69652897d6dac9fa97406ea9efa5d2))

### Bug Fixes

* **replay:** derive epoch from ticked ledger state ([c4fca44](https://github.com/lambdasistemi/cardano-stake-csmt/commit/c4fca4401692aac1ef7649193bcf6f8a563cbaec))
* **indexer:** skip Byron-era epoch boundaries ([606a947](https://github.com/lambdasistemi/cardano-stake-csmt/commit/606a947c3397fb0189348b7f2a54b7cf7e721c7d))
* **replay:** derive Byron epochs without EpochInfo horizon ([f0e3ae5](https://github.com/lambdasistemi/cardano-stake-csmt/commit/f0e3ae5fbf42ce6400c5f5573746c2e67d3c6297))

## 0.1.0.0

- Initial health/readiness scaffold.
