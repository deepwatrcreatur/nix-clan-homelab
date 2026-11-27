{ domain, hosts }:
{ lib, pkgs, ... }:
let
  sshHosts = lib.filterAttrs (_: host: host.includeSsh && !host.archived && host.sshTarget != null) hosts;
  settings = lib.mapAttrs' (
    name: host:
    lib.nameValuePair (lib.concatStringsSep " " ([ name ] ++ host.aliases)) (
      {
        HostName = host.sshTarget;
        User = host.sshUser;
      }
      # WHY: Clan host certificates name the canonical DNS name even when the endpoint is an IP.
      // lib.optionalAttrs host.migrated { HostKeyAlias = host.sshHostKeyAlias; }
    )
  ) sshHosts;
  knownHosts = lib.concatStrings (
    lib.mapAttrsToList (
      name: host:
      let
        legacyKey = if name == "emerald" then
          ../../../keys/emerald-host-ed25519.pub
        else
          ../../../keys/legacy-hosts + "/${name}-host-ed25519.pub";
        # WHY: a host joining clan keeps serving its old host key without a
        # certificate until its first clan deploy; pin the key clan holds
        # under the HostKeyAlias clan connects with, so that deploy (and the
        # age-key upload before it) can verify the host.
        clanKey = ../../../vars/per-machine + "/${name}/openssh/ssh.id_ed25519.pub/value";
        key = if host.migrated then clanKey else legacyKey;
        names =
          if host.migrated then [ host.fqdn ] else lib.unique ([ host.sshTarget name ] ++ host.aliases);
      in
      lib.optionalString (builtins.pathExists key)
        "${lib.concatStringsSep "," names} ${lib.concatStringsSep " " (lib.take 2 (lib.splitString " " (lib.removeSuffix "\n" (builtins.readFile key))))}\n"
    ) sshHosts
  );
  materialize = pkgs.writeShellScript "materialize-workstation-ssh-config" ''
    set -eu
    path="$1"
    if [ -L "$path" ]; then
      temp=$(mktemp -- "$path".XXXXXX)
      trap 'rm -f -- "$temp"' EXIT
      install -m 0600 -- "$path" "$temp"
      mv -Tf -- "$temp" "$path"
    elif [ -f "$path" ]; then
      chmod 0600 -- "$path"
    fi
  '';
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = settings // {
      "*" = {
        UserKnownHostsFile = "~/.ssh/known_hosts_dynamic ~/.ssh/known_hosts_managed";
        ControlMaster = "auto";
        ControlPersist = "15m";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        SendEnv = "LANG LC_* COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION";
        ForwardX11 = false;
        # SECURITY: forward the local agent only for an individual trusted connection (`ssh -A`).
        ForwardAgent = false;
        AddressFamily = "inet";
        ServerAliveInterval = 15;
        ServerAliveCountMax = 3;
        ConnectTimeout = 20;
      };
    };
  };
  # WHY: preserve Emerald's regular SSH config file across Home Manager generations.
  home.file.".ssh/config".force = true;
  home.activation.materializeSshConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${materialize} "$HOME/.ssh/config"
  '';
  home.file.".ssh/known_hosts_managed".text = knownHosts;
  home.packages = [
    (pkgs.writeShellApplication {
      name = "ssh-bash";
      runtimeInputs = [ pkgs.openssh ];
      text = builtins.readFile ./ssh-bash.sh;
    })
  ];
}
