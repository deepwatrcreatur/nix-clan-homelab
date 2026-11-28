{ fnox, llm-agents }:
{ config, lib, pkgs, ... }:
let
  fnoxLib = import (fnox + "/lib/default.nix") { inherit lib pkgs; };
  agentPackages = (pkgs.extend llm-agents.overlays.shared-nixpkgs).llm-agents;
  wrappedCommands = fnoxLib.defaultWrappedCommandSpecs {
    pkgs = pkgs // { inherit (agentPackages) claude-code gemini-cli; };
  };
  fnoxPackage = config.programs.fnox.package;
  credentialsDirectory = config.home.sessionVariables.WORKSTATION_CREDENTIALS_DIRECTORY or null;
  seedFiles = {
    ANTHROPIC_API_KEY = "anthropic-api-key";
    DEEPSEEK_API_KEY = "deepseek-api-key";
    GEMINI_API_KEY = "gemini-api-key";
    GITHUB_TOKEN = "github-token";
    GROK_API_KEY = "grok-api-key";
    OPENAI_API_KEY = "openai-api-key";
    OPENCODE_ZEN_API_KEY = "opencode-zen-api-key";
    OPENROUTER_API_KEY = "openrouter-api-key";
    Z_AI_API_KEY = "z-ai-api-key";
  };
  seedSecretSources = lib.mapAttrs
    (_: file:
      (lib.optional (credentialsDirectory != null) "${credentialsDirectory}/${file}")
      ++ [ "${config.home.homeDirectory}/.local/share/agenix-user-secrets/${file}" ])
    seedFiles;
  withCredential = variable: name: spec:
    if credentialsDirectory == null then
      spec
    else
      spec // {
        secrets = [ ];
        extraWrapperScript = ''
          if [ -z "''${${variable}:-}" ]; then
            ${variable}="$(cat -- ${lib.escapeShellArg "${credentialsDirectory}/${name}"})" || exit 1
            export ${variable}
          fi
        '';
      };
in
{
  imports = [ fnox.homeManagerModules.default ];
  programs.fnox = {
    enable = true;
    # WHY: the operator may have a writable fnox config with other credentials.
    configRelativePath = lib.mkIf (credentialsDirectory != null) "fnox/clan-defaults.toml";
    package = pkgs.fnox or fnox.packages.${pkgs.stdenv.hostPlatform.system}.default;
    # WHY: each workstation encrypts its own fnox store to its SSH identity;
    # configured source files restore values after the recipient changes.
    recipients = [ ];
    sshIdentity.enable = true;
    secretDefinitions = {
      DEEPSEEK_API_KEY.description = "DeepSeek API key";
      OPENAI_API_KEY.description = "OpenAI API key";
    };
    inherit seedSecretSources;
    wrappedCommands = {
      gemini-fnox = withCredential "GEMINI_API_KEY" "gemini-api-key" wrappedCommands.gemini-fnox;
      claude-fnox = withCredential "ANTHROPIC_API_KEY" "anthropic-api-key" {
        command = agentPackages.claude-code;
        binaryName = "claude";
        secrets = [
          {
            envVar = "ANTHROPIC_API_KEY";
            fnoxPath = "ANTHROPIC_API_KEY";
          }
        ];
      };
    };
  };
  home.packages = lib.mkIf config.programs.fnox.enable [
    (pkgs.callPackage ../../_packages/gh-fnox.nix { fnox = fnoxPackage; })
    (pkgs.callPackage ../../_packages/bw-fnox.nix { fnox = fnoxPackage; })
  ];
  xdg.configFile."nix/nix.conf".text = ''
    extra-experimental-features = nix-command flakes
  '';
}
