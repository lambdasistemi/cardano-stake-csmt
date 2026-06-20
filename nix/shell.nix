{ indexState }:

{ pkgs, ... }:

let
  indexTool = {
    index-state = indexState;
  };
in
{
  tools = {
    cabal = indexTool;
    fourmolu = indexTool;
    hlint = indexTool;
  };
  buildInputs = [
    pkgs.just
    pkgs.nixfmt
    pkgs.shellcheck
  ];
  shellHook = ''
    echo "Entering shell for cardano-stake-csmt development"
  '';
}
