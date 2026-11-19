# Disposable spike VM on pve-rog (beads nch-sny.1-.6).
{ den, inputs, ... }:
{
  den.aspects.clan-spike = {
    includes = [ den.aspects.base ];
    nixos =
      { config, pkgs, ... }:
      let
        clanVar = config.clan.core.vars.generators.spike-test.files.token.path;
        agenixVar = config.age.secrets.spike-agenix-test.path;
      in
      {
        imports = [
          ../../machines/clan-spike/disko.nix
          inputs.agenix.nixosModules.default
        ];
        system.stateVersion = "26.05";

        # nch-sny.3: one clan var and one agenix secret on the same machine.
        clan.core.vars.generators.spike-test = {
          files.token = { };
          runtimeInputs = [ pkgs.openssl ];
          script = ''openssl rand -hex 16 > "$out"/token'';
        };
        # The agenix secret is encrypted to the clan-managed host key
        # (vars/per-machine/clan-spike/openssh), which agenix uses by default.
        age.secrets.spike-agenix-test.file = ../../secrets/spike-agenix-test.age;
        # GOTCHA: agenix decrypts before sops-nix's setupSecrets, so the host
        # key it uses as identity must be installed in the earlier
        # setupSecretsForUsers stage (clan neededFor = "users").
        clan.core.vars.generators.openssh.files."ssh.id_ed25519".neededFor = "users";
        system.activationScripts.agenixInstall.deps = [ "setupSecretsForUsers" ];

        systemd.services.spike-secrets-check = {
          wantedBy = [ "multi-user.target" ];
          serviceConfig.Type = "oneshot";
          script = ''
            for f in ${clanVar} ${agenixVar}; do
              echo "$f: $(${pkgs.coreutils}/bin/wc -c < "$f") bytes"
            done
          '';
        };
      };
  };
}
