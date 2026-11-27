{
  lib,
  pkgs,
  hosts,
  domain,
  networks,
  unified,
}:
let
  legacyInventory = import (unified + "/lib/hosts.nix");
  legacyNetwork = legacyInventory.hosts;
  legacyComposition = lib.filterAttrs (_: host: !(host.archived or false)) (
    (import (unified + "/den/inventory/hosts.nix")) // (import (unified + "/den/inventory/darwin.nix"))
  );
  legacyBuilder = import (unified + "/lib/remote-builder.nix") { };

  active = lib.filterAttrs (name: host: !(host.archived || name == "clan-spike")) hosts;
  legacyNames = lib.unique (builtins.attrNames legacyNetwork ++ builtins.attrNames legacyComposition);
  withRole = role: lib.filterAttrs (_: host: builtins.elem role host.roles);
  # WHY: once unified retires a migrated host's system definition (lattitude,
  # unified #257), only its network entry is left to compare.
  composedInUnified = lib.filterAttrs (name: host: !host.migrated || legacyComposition ? ${name});
  builderClients = composedInUnified (withRole "remoteBuilderClient" hosts);
  cacheServers = withRole "cacheServer" hosts;
  derivedMetadataMatches = lib.concatLists (lib.mapAttrsToList (
    name: host:
    lib.optional (
      host.inventoryName != name
      || host.fqdn != "${name}.${domain}"
      || host.sshHostKeyAlias != host.fqdn
      || host.deployBackend != (if builtins.elem "router" host.roles then "deploy-rs" else "clan")
      || host.deployTarget != (if host.router == null then host.sshTarget else builtins.head (lib.splitString "/" host.router.lanAddress))
    ) "Derived host metadata differs for ${name}"
  ) hosts);

  sort = lib.sort builtins.lessThan;
  sameNames = actual: expected: sort actual == sort expected;

  networkMatches = lib.mapAttrsToList (
    name: legacy:
    let
      host = hosts.${name} or null;
    in
    lib.optional (
      host == null
      ||
        host.addresses != {
          ip = legacy.ip or null;
          hostname = legacy.hostname or null;
          sshHostname = legacy.sshHostname or null;
        }
      || host.sshUser != (legacy.sshUser or "deepwatrcreatur")
      || host.aliases != (legacy.aliases or [ ])
      || host.description != (legacy.description or "")
      || host.includeSsh != (legacy.includeSsh or true)
      || host.dhcpReservation != (legacy.dhcpReservation or null)
      || (if host.router == null then [ ] else host.router.ddnsServices) != (legacy.ddnsServices or [ ])
    ) "Network inventory differs for ${name}"
  ) legacyNetwork;

  compositionMatches = lib.mapAttrsToList (
    name: legacy:
    let
      host = hosts.${name} or null;
    in
    lib.optional (
      host == null
      || host.kind != legacy.kind
      || host.system != legacy.system
      || host.sshUser != (legacy.username or (legacyNetwork.${name}.sshUser or "deepwatrcreatur"))
    ) "System inventory differs for ${name}"
  ) legacyComposition;

  errors =
    lib.optional (!sameNames (builtins.attrNames active) legacyNames) "Active host names differ"
    ++ derivedMetadataMatches
    ++ lib.optional (networks != legacyInventory.networks) "Network topology differs"
    ++ lib.concatLists networkMatches
    ++ lib.concatLists compositionMatches
    ++ lib.optional (
      !sameNames (builtins.attrNames (
        lib.filterAttrs (_: host: host.kind == "nixos") builderClients
      )) legacyBuilder.nixosHosts
    ) "NixOS builder clients differ"
    ++ lib.optional (
      !sameNames (builtins.attrNames (
        lib.filterAttrs (_: host: host.kind != "nixos") builderClients
      )) legacyBuilder.nonNixosHosts
    ) "Non-NixOS builder clients differ"
    ++ lib.optional (
      !sameNames (lib.concatLists (
        lib.mapAttrsToList (name: host: [ name ] ++ host.cacheAliases) cacheServers
      )) legacyBuilder.cacheHosts
    ) "Cache servers differ"
    ++ lib.optional (
      !(lib.all (host: lib.all (alias: builtins.elem alias host.aliases) host.cacheAliases) (
        builtins.attrValues cacheServers
      ))
    ) "Legacy cache names must be host aliases"
    ++ lib.optional (
      !sameNames (builtins.attrNames (withRole "router" active)) (
        builtins.attrNames (
          lib.filterAttrs (_: host: builtins.elem "router-router" (host.aspectsList or [ ])) legacyComposition
        )
      )
    ) "Router-class hosts differ"
    ++ lib.optional (
      !sameNames (builtins.attrNames (composedInUnified (withRole "desktop" active))) (
        builtins.attrNames (lib.filterAttrs (_: host: host.isDesktop or false) legacyComposition)
      )
    ) "Desktops differ";
in
assert lib.assertMsg (errors == [ ]) (lib.concatStringsSep "\n" errors);
pkgs.runCommand "inventory-matches-unified" { } "touch $out"
