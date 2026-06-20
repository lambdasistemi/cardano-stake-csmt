{
  description = "Cardano stake CSMT service scaffold";

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys = [ "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ=" ];
  };

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    CHaP = {
      url = "github:intersectmbo/cardano-haskell-packages?ref=repo";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      haskellNix,
      CHaP,
      ...
    }:
    let
      version = self.dirtyShortRev or self.shortRev or "dirty";
    in
    (flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-darwin" ] (
      system:
      let
        pkgs = import nixpkgs {
          overlays = [
            haskellNix.overlay
            (final: prev: {
              haskell-nix = prev.haskell-nix // {
                extraPkgconfigMappings = (prev.haskell-nix.extraPkgconfigMappings or { }) // {
                  libsodium = [ "libsodium" ];
                  libsecp256k1 = [ "secp256k1" ];
                  libblst = [ "blst" ];
                };
              };
            })
          ];
          inherit system;
        };
        project = import ./nix/project.nix {
          indexState = "2026-05-01T00:00:00Z";
          inherit CHaP;
          inherit pkgs;
        };
      in
      {
        packages = project.packages // {
          default = project.packages.cardano-stake-csmt;
        };
        inherit (project) devShells;
      }
    ))
    // {
      inherit version;
    };
}
