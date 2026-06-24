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
    dev-assets = {
      url = "github:paolino/dev-assets";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cardano-node.url = "github:IntersectMBO/cardano-node/11.0.1";
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
      dev-assets,
      cardano-node,
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
          cardano-node-pkgs = cardano-node.packages.${system};
        };
        packageVersion =
          let
            versionLine = builtins.head (
              builtins.filter (line: builtins.match "[[:space:]]*version:[[:space:]]+.*" line != null) (
                pkgs.lib.splitString "\n" (builtins.readFile ./cardano-stake-csmt.cabal)
              )
            );
          in
          builtins.head (builtins.match "[[:space:]]*version:[[:space:]]+([^[:space:]]+).*" versionLine);
        sourceRevision = self.shortRev or (builtins.substring 0 7 (self.dirtyShortRev or "dirty"));
        devArtifactVersion = "${packageVersion}-${sourceRevision}";
        cardano-stake-csmt =
          pkgs.runCommand "cardano-stake-csmt-${packageVersion}"
            {
              nativeBuildInputs = [ pkgs.makeWrapper ];
              meta.mainProgram = "cardano-stake-csmt";
            }
            ''
              mkdir -p "$out/bin"
              makeWrapper ${project.packages.cardano-stake-csmt}/bin/cardano-stake-csmt \
                "$out/bin/cardano-stake-csmt"
            '';
        linuxReleasePackages = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          linux-release-artifacts = import ./nix/linux-release.nix {
            inherit
              pkgs
              system
              packageVersion
              ;
            package = project.packages.cardano-stake-csmt;
          };
          linux-dev-release-artifacts = import ./nix/linux-release.nix {
            inherit
              pkgs
              system
              packageVersion
              ;
            artifactVersion = devArtifactVersion;
            package = project.packages.cardano-stake-csmt;
          };
          linux-artifact-smoke = import ./nix/linux-artifact-smoke.nix {
            inherit pkgs system;
          };
          docker-image = import ./nix/docker-image.nix {
            inherit pkgs project version;
          };
        };
        darwinReleasePackages = pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
          darwin-release-artifacts = import ./nix/darwin-release.nix {
            inherit pkgs packageVersion;
            mkDarwinHomebrewBundle = dev-assets.lib.mkDarwinHomebrewBundle;
            package = cardano-stake-csmt;
          };
          darwin-dev-homebrew-artifacts = import ./nix/darwin-release.nix {
            inherit pkgs packageVersion;
            mkDarwinHomebrewBundle = dev-assets.lib.mkDarwinHomebrewBundle;
            artifactVersion = devArtifactVersion;
            releaseTag = "dev-homebrew";
            formulaName = "cardano-stake-csmt-dev";
            formulaClass = "CardanoStakeCsmtDev";
            formulaVersion = devArtifactVersion;
            formulaExtraLines = "\n  conflicts_with \"cardano-stake-csmt\", because: \"both install the same command-line tool\"";
            package = cardano-stake-csmt;
          };
        };
      in
      {
        packages =
          project.packages
          // {
            inherit cardano-stake-csmt;
            default = cardano-stake-csmt;
          }
          // linuxReleasePackages
          // darwinReleasePackages;
        apps = pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          linux-artifact-smoke = {
            type = "app";
            program = "${linuxReleasePackages.linux-artifact-smoke}/bin/linux-artifact-smoke";
          };
        };
        inherit (project) devShells;
      }
    ))
    // {
      inherit version;
    };
}
