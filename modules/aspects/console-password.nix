# Console (tty) passwords for root and the operator account, as clan vars.
# WHY: SSH uses keys only, but a router's recovery path is its console
# (failover rehearsal, router-apply reverts). Without a password both
# accounts were locked ('!'), and console login failed (nch-sny.11).
# Include per clan host: it declares a clan var, so it cannot go in
# nixos-base, which also builds outside clan (workstation-niri-eval).
{ config, lib, ... }:
let
  aspectModule = config.den.aspects.console-password.nixos;
in
{
  # Check: hashes reach /etc/shadow on a fresh host, a locked account is
  # unlocked on the next activation, and a password changed by hand stays.
  perSystem = { pkgs, ... }:
  let
    # Same derivation as in the node, so the script reads the exact file.
    hash' = user: pw: pkgs.runCommand "${user}-hash" { } ''
      echo -n ${pw} | ${pkgs.mkpasswd}/bin/mkpasswd -m yescrypt --stdin > $out
    '';
  in
  {
    checks.console-password = pkgs.testers.runNixOSTest {
      name = "console-password";
      nodes.machine = { lib, ... }:
        let
          hash = hash';
        in
        {
        imports = [ aspectModule ];
        # Stub for clan's vars: only the file paths the aspect reads.
        options.clan = lib.mkOption { type = lib.types.anything; default = { }; };
        config = {
          # INVARIANT: the hash files must exist before the users step, as
          # /run/secrets-for-users does on a real host; /etc does not yet.
          clan.core.vars.generators.console-password.files = {
            root.path = "${hash "root" "rootpw"}";
            deepwatrcreatur.path = "${hash "deepwatrcreatur" "userpw"}";
          };
          users.users.deepwatrcreatur.isNormalUser = true;
        };
      };
      testScript = ''
        def shadow(user):
            return machine.succeed(f"getent shadow {user} | cut -d: -f2").strip()

        def wanted(user):
            return paths[user]

        paths = {
            "root": machine.succeed("cat ${hash' "root" "rootpw"}").strip(),
            "deepwatrcreatur": machine.succeed("cat ${hash' "deepwatrcreatur" "userpw"}").strip(),
        }
        machine.wait_for_unit("multi-user.target")
        with subtest("fresh host: both accounts get the stored hash"):
            for u in ["root", "deepwatrcreatur"]:
                assert shadow(u) == wanted(u), f"{u}: {shadow(u)!r}"

        with subtest("a locked account is unlocked on activation"):
            machine.succeed("usermod -p '!' root")
            assert shadow("root") == "!"
            machine.succeed("/run/current-system/activate")
            assert shadow("root") == wanted("root")

        with subtest("a password changed by hand is kept"):
            # A random password, so no credential-looking literal is in git.
            machine.succeed('echo "deepwatrcreatur:$(head -c 12 /dev/urandom | base64)" | chpasswd')
            manual = shadow("deepwatrcreatur")
            machine.succeed("/run/current-system/activate")
            assert shadow("deepwatrcreatur") == manual
      '';
    };
  };

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
