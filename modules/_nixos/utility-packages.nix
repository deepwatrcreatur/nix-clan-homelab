# Common system utilities, network tools, and secrets management tools.
{ pkgs, lib, ... }:
{
  # WHY: baseline utilities available on every fleet host for diagnostics and administration
  environment.systemPackages =
    with pkgs;
    [
      # System and performance tools
      hyperfine
      lsof
      procs
      tailspin

      # Archive tools
      gzip
      bzip2
      xz

      # Network tools
      curl
      wget
      rsync
      mosh
      nmap
      openssl
      attic-client

      # Nix helpers
      nix-prefetch-git
      nix-prefetch-github
      nix-index

      # Secrets management tools
      sops
      age
      rage
      ssh-to-age
      # UPSTREAM: ryantm/agenix compatibility wrapper for secrets.nix format
      (writeShellScriptBin "agenix-edit" ''
        exec nix run github:ryantm/agenix -- -e "$@"
      '')
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      pciutils
      iotop
      strace
      wl-clipboard
      netcat-openbsd
      ethtool
      tcpdump
      # WHY: iputils no longer ships ping6; resolve ping via PATH so NixOS wrapper is used
      (writeShellScriptBin "ping6" ''exec ping -6 "$@"'')
    ];
}
