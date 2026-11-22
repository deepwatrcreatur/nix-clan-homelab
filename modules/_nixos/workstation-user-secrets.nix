{ config, lib, pkgs, ... }:
let
  user = "deepwatrcreatur";
  names = [
    "anthropic-api-key"
    "atuin-key-b64"
    "bitwarden-data"
    "deepseek-api-key"
    "gemini-api-key"
    "github-token"
    "grok-api-key"
    "oauth-creds"
    "openai-api-key"
    "opencode-zen-api-key"
    "openrouter-api-key"
    "rclone-conf"
    "z-ai-api-key"
  ];
  files = config.clan.core.vars.generators.workstation-user-secrets.files;
in
{
  clan.core.vars.generators.workstation-user-secrets = {
    share = true;
    prompts = lib.genAttrs names (name: {
      description = "Existing workstation credential ${name}";
      type = "multiline-hidden";
    });
    files = lib.genAttrs names (_: {
      owner = user;
      mode = "0400";
    });
    runtimeInputs = [ pkgs.coreutils ];
    script = lib.concatMapStringsSep "\n" (name: ''cp "$prompts/${name}" "$out/${name}"'') names;
  };

  home-manager.users.${user} =
    { config, lib, ... }:
    let
      restore = [
        { source = files.atuin-key-b64.path; target = "${config.xdg.dataHome}/atuin/key"; }
        { source = files.bitwarden-data.path; target = "${config.xdg.configHome}/Bitwarden CLI/data.json"; }
        { source = files.oauth-creds.path; target = "${config.home.homeDirectory}/.gemini/oauth_creds.json"; }
        { source = files.rclone-conf.path; target = "${config.xdg.configHome}/rclone/rclone.conf"; }
      ];
    in
    {
      home.packages = [ pkgs.gnupg pkgs.sops ];
      home.sessionVariables.WORKSTATION_CREDENTIALS_DIRECTORY = dirOf files.github-token.path;
      home.file.".gnupg/public-key.asc".source = ../../keys/deepwatrcreatur-gpg.asc;
      xdg.configFile."git/github-token".source =
        config.lib.file.mkOutOfStoreSymlink files.github-token.path;

      home.activation.restoreWorkstationCredentials = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        # These applications maintain their own writable state after the first import.
        seed_credential() (
          local source="$1" target="$2" directory temporary
          [[ ! -e "$target" && ! -L "$target" ]] || return 0
          directory="$(dirname -- "$target")"
          mkdir -p -m 0700 -- "$directory"
          temporary="$(mktemp -- "$directory/.clan-credential.XXXXXX")"
          trap 'rm -f -- "$temporary"' EXIT
          install -m 0600 -- "$source" "$temporary"
          if ! ln -T -- "$temporary" "$target"; then
            [[ -e "$target" || -L "$target" ]]
          fi
        )
        if [[ ! -v DRY_RUN ]]; then
          ${lib.concatMapStringsSep "\n" ({ source, target }: ''
            seed_credential ${lib.escapeShellArg source} ${lib.escapeShellArg target}
          '') restore}
        fi
      '';
    };
}
