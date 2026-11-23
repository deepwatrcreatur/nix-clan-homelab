{ ... }:
{
  den.aspects.desktop-network-shares.nixos =
    { pkgs, ... }:
    let
      wsDiscoveryPort = 3702;
      wsddReplyPort = 37020;
      wsdd = pkgs.writeShellScriptBin "wsdd" ''
        exec ${pkgs.wsdd}/bin/wsdd --source-port ${toString wsddReplyPort} "$@"
      '';
    in
    {
      programs.strata.enable = true;
      services.gvfs.enable = true;
      services.avahi = {
        enable = true;
        nssmdns4 = true;
        openFirewall = true;
      };
      environment.systemPackages = [ wsdd ];
      networking.firewall.allowedUDPPorts = [ wsDiscoveryPort wsddReplyPort ];
    };
}
