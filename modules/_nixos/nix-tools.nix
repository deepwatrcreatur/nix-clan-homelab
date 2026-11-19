# Nix analysis, diagnostics, formatters, and environment tools.
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    devenv
    direnv
    lorri
    nix-health
    nix-inspect
    nix-visualize
    nh
    nix-output-monitor
    nix-tree
    nvd
    nixfmt
    nixpkgs-fmt
    statix
    nil
    nixd
  ];
}
