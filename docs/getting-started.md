# Getting started

## Prerequisites

Use Nix with flake support enabled. The flake pins the Haskell toolchain and development utilities used by the project.

## Development shell

Enter the project shell:

```sh
nix develop
```

The shell provides Cabal, Fourmolu, HLint, Just, Nixfmt, and ShellCheck.

## Common checks

Run the scaffold checks through Just:

```sh
just build
just unit
just e2e
just format-check
just hlint
```

Run the local gate:

```sh
./gate.sh
```

## Documentation

Build the documentation with the shared MkDocs environment:

```sh
nix develop github:paolino/dev-assets?dir=mkdocs --quiet -c mkdocs build --strict --site-dir site
```
