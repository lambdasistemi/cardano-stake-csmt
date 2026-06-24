{
  pkgs,
  project,
  version,
  ...
}:

pkgs.dockerTools.buildImage {
  name = "ghcr.io/lambdasistemi/cardano-stake-csmt/cardano-stake-csmt";
  tag = version;
  config = {
    EntryPoint = [ "cardano-stake-csmt" ];
  };
  copyToRoot = pkgs.buildEnv {
    name = "image-root";
    paths = [ project.packages.cardano-stake-csmt ];
  };
}
