# den: hosts, users and aspects. Hosts are instantiated by clan, not den.
{
  config,
  inputs,
  den,
  lib,
  ...
}:
let
  hosts = config.homelab.hosts;
  clanHosts = lib.filterAttrs (
    _: host: (host.migrated || host.clanCandidate) && !host.archived
  ) hosts;
  bySystem = lib.groupBy (name: clanHosts.${name}.system) (builtins.attrNames clanHosts);
in
{
  imports = [ inputs.den.flakeModule ];

  den.schema.user.classes = lib.mkDefault [ "homeManager" ];
  # WHY: a user's own nixos content (SSH keys, groups) belongs on every host
  # the user is on; opt into den's explicit form (denful/den#694).
  den.schema.host.includes = [ den.batteries.user-aspects ];
  den.default.homeManager.home.stateVersion = lib.mkDefault "26.05";

  den.hosts = lib.mapAttrs (
    _: names:
    lib.genAttrs names (name: {
      intoAttr = [ ];
      users.deepwatrcreatur = { };
    })
  ) bySystem;
}
