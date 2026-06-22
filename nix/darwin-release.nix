{
  pkgs,
  mkDarwinHomebrewBundle,
  packageVersion,
  artifactVersion ? packageVersion,
  releaseTag ? "v${packageVersion}",
  formulaName ? "cardano-stake-csmt",
  formulaClass ? "CardanoStakeCsmt",
  formulaVersion ? artifactVersion,
  formulaExtraLines ? "",
  package,
}:

let
  mkBundle = mkDarwinHomebrewBundle { inherit pkgs; };
in
mkBundle {
  pname = "cardano-stake-csmt";
  version = packageVersion;
  inherit
    artifactVersion
    releaseTag
    formulaName
    formulaClass
    formulaVersion
    formulaExtraLines
    ;
  owner = "lambdasistemi";
  repo = "cardano-stake-csmt";
  desc = "Serve Cardano stake CSMT proofs";
  homepage = "https://github.com/lambdasistemi/cardano-stake-csmt";
  executables = {
    cardano-stake-csmt = package;
  };
  executableNames = [ "cardano-stake-csmt" ];
  formulaTest = ''
    assert_predicate bin/"cardano-stake-csmt", :executable?
  '';
  smokeCommands = [ ''test -x "$bundle/bin/cardano-stake-csmt"'' ];
}
