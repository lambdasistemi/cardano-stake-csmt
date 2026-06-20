{
  CHaP,
  indexState,
  pkgs,
}:

let
  shell = import ./shell.nix { inherit indexState; };
  fix-libs =
    { lib, pkgs, ... }:
    {
      packages.cardano-crypto-praos.flags.external-libsodium-vrf = false;
      packages.cardano-crypto-praos.components.library.pkgconfig = lib.mkForce [ [ pkgs.libsodium ] ];
      packages.cardano-crypto-class.components.library.pkgconfig = lib.mkForce [
        [
          pkgs.libsodium
          pkgs.secp256k1
          pkgs.blst
        ]
      ];
    };
  mkProject =
    { pkgs, ... }:
    {
      name = "cardano-stake-csmt";
      src = ./..;
      compiler-nix-name = "ghc9123";
      shell = shell { inherit pkgs; };
      modules = [
        fix-libs
        (
          { ... }:
          {
            packages.cardano-stake-csmt.flags.werror = true;
          }
        )
      ];
      inputMap = {
        "https://chap.intersectmbo.org/" = CHaP;
      };
    };
  project = pkgs.haskell-nix.cabalProject' mkProject;
in
{
  devShells.default = project.shell;
  inherit project;
  packages.cardano-stake-csmt = project.hsPkgs.cardano-stake-csmt.components.exes.cardano-stake-csmt;
  packages.default = project.hsPkgs.cardano-stake-csmt.components.exes.cardano-stake-csmt;
  packages.unit-tests = project.hsPkgs.cardano-stake-csmt.components.tests.unit-tests;
  packages.e2e-tests = project.hsPkgs.cardano-stake-csmt.components.tests.e2e-tests;
}
