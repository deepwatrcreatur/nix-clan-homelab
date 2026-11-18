# User-side server persona aspect.
# Ported from unified users/deepwatrcreatur/aspects/server.nix and den/aspects/user-server.nix.
{ den, ... }:
{
  den.aspects.user-server = {
    nixos =
      { ... }:
      {
        # WHY: bash login shell preserves non-interactive SSH tooling; interactive sessions drop into fish
        custom.fishInteractiveShell.users = [ "deepwatrcreatur" ];
      };

    homeManager =
      { pkgs, ... }:
      {
        # TODO(nch-sny.11): agenix user secrets (github-token at .config/git/github-token)
        # TODO(nch-sny.11): user-level netrc for cache authentication if needed

        programs.bash.enable = true;
        programs.fish.enable = true;

        home.packages = with pkgs; [
          htop
        ];
      };
  };
}
