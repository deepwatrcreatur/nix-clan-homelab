{ config, lib, pkgs, ... }:
let
  user = "deepwatrcreatur";
  names = [
    "anthropic-api-key"
    "atuin-key-b64"
    "bitwarden-data"
    "bitwarden-session"
    "deepseek-api-key"
    "gemini-api-key"
    "github-token"
    "gpg-private-key"
    "grok-api-key"
    "oauth-creds"
    "openai-api-key"
    "opencode-zen-api-key"
    "openrouter-api-key"
    "rclone-conf"
    "technitium-api-key"
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
    { config, ... }:
    {
      home.packages = [ pkgs.gnupg pkgs.sops ];
      home.file.".gnupg/public-key.asc".source = ../../keys/deepwatrcreatur-gpg.asc;
      xdg.configFile."git/github-token".source =
        config.lib.file.mkOutOfStoreSymlink files.github-token.path;
    };
}
