{ indexState, pkgs }:

let
  shell = import ./shell.nix { inherit indexState; };
  mkProject =
    { pkgs, ... }:
    {
      name = "cardano-stake-csmt";
      src = ./..;
      compiler-nix-name = "ghc9123";
      shell = shell { inherit pkgs; };
      modules = [
        (
          { ... }:
          {
            packages.cardano-stake-csmt.flags.werror = true;
          }
        )
      ];
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
