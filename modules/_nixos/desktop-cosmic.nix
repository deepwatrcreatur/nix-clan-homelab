{
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./sessions/cosmic.nix
  ];

  home-manager.users.deepwatrcreatur = {
    programs.vicinae.enable = true;

    xdg.configFile."cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom".text = ''
      {
          (
              modifiers: [Alt],
              key: "space",
              description: Some("Vicinae Launcher"),
          ): Spawn("${pkgs.vicinae}/bin/vicinae toggle"),
      }
    '';
  };
}
