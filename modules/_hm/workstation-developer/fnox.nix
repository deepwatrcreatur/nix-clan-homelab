{ fnox, llm-agents }:
{ config, lib, pkgs, ... }:
let
  fnoxLib = import (fnox + "/lib/default.nix") { inherit lib pkgs; };
  agentPackages = (pkgs.extend llm-agents.overlays.shared-nixpkgs).llm-agents;
  wrappedCommands = fnoxLib.defaultWrappedCommandSpecs {
    pkgs = pkgs // { inherit (agentPackages) claude-code gemini-cli; };
  };
  fnoxPackage = config.programs.fnox.package;
in
{
  imports = [ fnox.homeManagerModules.default ];
  programs.fnox = {
    enable = true;
    package = pkgs.fnox or fnox.packages.${pkgs.stdenv.hostPlatform.system}.default;
    recipients = [
      "age17mn5lnlh2mgttp950wc7a2nl9kphewa4jj8e0uhlv3svx68a54vqyngcyr"
      "age1awqed0la6x3rr39et8fjruw42mf8v2sqct78mcjzx5d226gcx9nqrjdmjz"
    ];
    wrappedCommands = {
      inherit (wrappedCommands) gemini-fnox;
      claude-fnox = {
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
