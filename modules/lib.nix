# Shared flake library functions.
{
  flake.lib = {
    diskoLayout = import ./_lib/disko-layout.nix;
  };
}
