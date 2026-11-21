{ inputs }:
{ pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
in
{
  home.packages = with pkgs; [
    age
    ansible
    bandwhich

    # Terminal monitoring and diagnostics
    bottom
    btop
    glances
    bun
    just
    cloc
    curl
    difftastic
    dig
    dua
    dust
    dysk
    fastfetch
    (callPackage ./spinnyfetch.nix { })
    file
    flow-control
    gdu
    glow
    gping
    grex
    iperf3
    jless
    jnv
    jq
    killall
    inputs.leaf.packages.${system}.default
    lsd
    inputs.nix-markit.packages.${system}.markit
    navi
    ncdu
    neovim
    netcat
    nmap
    ouch
    pstree
    python3
    sad
    sshs
    wget
    xdg-ninja
    xh
    yamllint
    yq
  ];
}
