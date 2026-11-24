{ config, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      homeConfig = config.flake.homeConfigurations."root@pve-strix";
      home = homeConfig.config;
      packages = builtins.sort builtins.lessThan (map (p: p.pname or p.name) home.home.packages);
      files = builtins.sort builtins.lessThan (builtins.attrNames home.home.file);
      actual = {
        username = home.home.username;
        homeDirectory = home.home.homeDirectory;
        stateVersion = home.home.stateVersion;
        packageCount = builtins.length packages;
        packageNamesHash = builtins.hashString "sha256" (builtins.toJSON packages);
        fileTargetCount = builtins.length files;
        fileTargetsHash = builtins.hashString "sha256" (builtins.toJSON files);
      };
      expected = builtins.fromJSON (builtins.readFile ../checks/pve-strix-home-reference.json);
      activationPackage = homeConfig.activationPackage;
      dryRunGuard = home.home.activation.ensureDryRunVariable.data;
    in
    {
      checks.pve-strix-home-parity =
        if actual != expected || dryRunGuard != ":" then
          throw "PVE-Strix Home Manager parity or activation mode changed. Expected ${builtins.toJSON expected}; got ${builtins.toJSON actual}"
        else
          pkgs.runCommand "pve-strix-home-parity"
            {
              nativeBuildInputs = [ activationPackage ];
            }
            ''
              test -x ${activationPackage}/activate
              touch "$out"
            '';
    };
}
