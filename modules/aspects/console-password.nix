# Console (tty) passwords for root and the operator account, as clan vars.
# WHY: SSH uses keys only, but a router's recovery path is its console
# (failover rehearsal, router-apply reverts). Without a password both
# accounts were locked ('!'), and console login failed (nch-sny.11).
# Include per clan host: it declares a clan var, so it cannot go in
# nixos-base, which also builds outside clan (workstation-niri-eval).
{ ... }:
{
  den.aspects.console-password.nixos =
    { config, lib, pkgs, ... }:
    let
      gen = config.clan.core.vars.generators.console-password;
      users = [ "root" "deepwatrcreatur" ];
    in
    {
      # SECURITY: the plaintext prompt never leaves the generator; only the
      # yescrypt hashes are stored (sops-encrypted) and installed.
      clan.core.vars.generators.console-password = {
        share = true;
        prompts = lib.genAttrs users (user: {
          description = "Console password for ${user} (stored only as a hash)";
          type = "hidden";
        });
        files = lib.genAttrs users (_: {
          # INVARIANT: users are created before normal secrets are installed.
          neededFor = "users";
        });
        runtimeInputs = [ pkgs.mkpasswd ];
        script = lib.concatMapStrings (user: ''
          mkpasswd -m yescrypt --stdin < "$prompts/${user}" > "$out/${user}"
        '') users;
      };

      users.users = lib.genAttrs users (user: {
        hashedPasswordFile = gen.files.${user}.path;
      });

      # GOTCHA: with mutableUsers (the default) NixOS doesn't replace the
      # password of an existing account, so a host that already exists with
      # a locked account keeps it. Unlock exactly that case; a password
      # changed on the host by hand is left alone (same as unified).
      system.activationScripts.console-password = {
        deps = [ "users" ];
        text = lib.concatMapStrings (user: ''
          hash_file=${lib.escapeShellArg gen.files.${user}.path}
          if [ -s "$hash_file" ]; then
            current=$(${pkgs.gnugrep}/bin/grep "^${user}:" /etc/shadow | ${pkgs.coreutils}/bin/cut -d: -f2)
            case "$current" in
              '!'*|'*'|"")
                echo "${user}:$(${pkgs.coreutils}/bin/cat "$hash_file")" | ${pkgs.shadow}/bin/chpasswd -e
                ;;
            esac
          fi
        '') users;
      };
    };
}
