{ config, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      mkHomeParityCheck =
        hostName:
        let
          homeConfig = config.flake.homeConfigurations."root@${hostName}";
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
          expected = builtins.fromJSON (builtins.readFile (../checks + "/${hostName}-home-reference.json"));
          activationPackage = homeConfig.activationPackage;
          dryRunGuard = home.home.activation.ensureDryRunVariable.data;
          atticActivation = home.home.activation.attic-config;
        in
        if
          actual != expected
          || dryRunGuard != ":"
          || !(lib.elem "linkGeneration" atticActivation.after)
          || !(lib.elem "userSecretsActivation" atticActivation.after)
          || !(lib.hasInfix "config_template=" atticActivation.data)
          || !(lib.hasInfix "umask 077" atticActivation.data)
          || !(lib.hasInfix "chmod 600" atticActivation.data)
        then
          throw "${hostName} Home Manager parity or activation ordering changed. Expected ${builtins.toJSON expected}; got ${builtins.toJSON actual}"
        else
          pkgs.runCommand "${hostName}-home-parity"
            {
              nativeBuildInputs = [ activationPackage ];
            }
            ''
              test -x ${activationPackage}/activate
              touch "$out"
            '';
    in
    {
      checks.pve-strix-home-parity = mkHomeParityCheck "pve-strix";
      checks.pve-rog-home-parity = mkHomeParityCheck "pve-rog";
    };
}
