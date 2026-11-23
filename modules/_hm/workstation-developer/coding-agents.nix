{ inputs }:
# modules/home-manager/common/coding-agents.nix
# AI coding agents configuration
# Uses nix-rtk for RTK hooks, llm-agents.nix for packages
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.coding-agents;
  system = pkgs.stdenv.hostPlatform.system;
  # WHY: nix-rtk's hook module installs pkgs.rtk; keep the CLI on that same version to avoid a bin/rtk collision.
  agentPackages = (pkgs.extend inputs.llm-agents.overlays.shared-nixpkgs).llm-agents // { rtk = pkgs.rtk; };
in
{
  imports = [
    inputs.nix-rtk.homeManagerModules.default
    ./agent-guards.nix
  ];

  options.programs.coding-agents.enable = lib.mkEnableOption "AI coding agent packages and integrations" // {
    default = true;
  };

  config = lib.mkIf cfg.enable {
    programs.agent-guards.enable = lib.mkDefault true;

    # Enable RTK hooks with Claude enabled by default
    programs.rtk-hooks = {
      enable = lib.mkDefault true;
      integrations = {
        claude.enable = true;
        codex.enable = true;
        gemini.enable = true;
        opencode.enable = true;
      };
    };

    home.file.".claude/.keep".text = "";

    # rtkHooks writes RTK.md into ~/.claude and runs before home.file links are
    # created, so .keep alone cannot create it on a host's first activation.
    home.activation.ensureClaudeDir = lib.hm.dag.entryBetween [ "rtkHooks" ] [ "writeBoundary" ] ''
      run mkdir -p "$HOME/.claude"
    '';

    # Install coding agent packages from llm-agents overlay.
    home.packages =
      with agentPackages;
      [
        # Core agents
        rtk
        claude-code
        opencode
        codex
        gemini-cli
        amp
        copilot-cli
        cursor-agent
        forgecode
        goose-cli
        kilocode-cli
        pi
        crush
        agent-deck
        workmux
        inputs.nix-deepseek-harness.packages.${system}.default

        # Utilities
        ccstatusline
      ]
      ++ lib.optionals (agentPackages ? ccusage) [ ccusage ]
      ++ lib.optionals (agentPackages ? antigravity-cli) [ antigravity-cli ]
      ++ lib.optionals (agentPackages ? ccusage-amp) [ ccusage-amp ]
      ++ lib.optionals (agentPackages ? ccusage-codex) [ ccusage-codex ]
      ++ lib.optionals (agentPackages ? ccusage-opencode) [ ccusage-opencode ]
      # WHY: Codex's Linux sandbox expects bwrap on PATH; without it Codex warns
      # and falls back to its bundled copy.
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.bubblewrap ];
  };
}
