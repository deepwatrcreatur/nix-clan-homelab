{
  den,
  inputs,
  ...
}:
let
  system = "x86_64-linux";
  # WHY: keep Unified's fnox module revision local to this transitional home.
  proxmoxInputs = inputs // {
    fnox = inputs.fnox-pve;
  };
  proxmoxPkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        fnox = inputs.fnox-pve.packages.${system}.default;
        markit = inputs.nix-markit.packages.${system}.markit;
        leaf = inputs.leaf.packages.${system}.default;
      })
    ]
    ++ import (inputs.unified-pve.outPath + "/overlays/packages.nix") {
      nixpkgsLib = inputs.nixpkgs.lib;
    };
  };
in
let
  mkProxmoxHome = hostName: {
    pkgs = proxmoxPkgs;
    instantiate =
      { pkgs, modules, ... }:
      inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs modules;
        extraSpecialArgs = {
          inputs = proxmoxInputs;
          inherit hostName;
          isDesktop = false;
        };
      };
  };
in
{
  den.homes.${system} = {
    "root@pve-strix" = mkProxmoxHome "pve-strix";
    "root@pve-rog" = mkProxmoxHome "pve-rog";
  };

  den.aspects."root@pve-strix".includes = [ den.batteries.define-user ];
  den.aspects."root@pve-rog".includes = [ den.batteries.define-user ];

  den.aspects.root.homeManager =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      atticTemplate = config.home.file.".config/attic/config.toml".source;
      atticTokenPlaceholder =
        name:
        "@NIX_ATTIC_INFRA_TOKEN_${lib.toUpper (builtins.replaceStrings [ "-" "." ] [ "_" "_" ] name)}_${
          builtins.substring 0 8 (builtins.hashString "sha256" name)
        }@";
      atticTokenSubstitutions = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          name: server:
          let
            tokenPath = lib.escapeShellArg server.tokenPath;
            placeholder = lib.escapeShellArg (atticTokenPlaceholder name);
          in
          ''
            if [[ ! -r ${tokenPath} ]]; then
              echo "Attic token is unavailable for ${name}; retaining the prior backup" >&2
              exit 1
            fi

            token="$(${pkgs.coreutils}/bin/cat ${tokenPath})"
            placeholder=${placeholder}
            escaped_token=$(printf '%s' "$token" | ${pkgs.gnused}/bin/sed 's/[\\&|]/\\&/g')
            ${pkgs.gnused}/bin/sed "s|$placeholder|$escaped_token|g" "$temp_file" > "$temp_file.rendered"
            ${pkgs.coreutils}/bin/mv "$temp_file.rendered" "$temp_file"
          ''
        ) config.programs.attic-client.servers
      );
    in
    {
      # WHY: retain the Proxmox root home path while this standalone output
      # replaces Unified's profile; the system configuration remains in Unified.
      home.homeDirectory = lib.mkForce "/root";
      # WHY: Home Manager treats even an empty DRY_RUN variable as dry-run
      # mode. The upstream compatibility workaround would skip managed links.
      home.activation.ensureDryRunVariable = lib.mkForce (lib.hm.dag.entryBefore [ "attic-config" ] ":");
      # WHY: render the tokenized template only after Home Manager links it;
      # after secrets are materialized, or it reads an outdated token.
      home.activation.attic-config = lib.mkForce (
        lib.hm.dag.entryAfter [ "linkGeneration" "userSecretsActivation" ] ''
          config_dir=${lib.escapeShellArg "${config.home.homeDirectory}/.config/attic"}
          config_file="$config_dir/config.toml"
          config_template=${lib.escapeShellArg (toString atticTemplate)}

          if [[ -f "$config_file" ]]; then
            umask 077
            temp_file="$(${pkgs.coreutils}/bin/mktemp "$config_dir/config.toml.tmp.XXXXXX")"
            trap '${pkgs.coreutils}/bin/rm -f "$temp_file" "$temp_file.rendered"' EXIT
            ${pkgs.coreutils}/bin/cp "$config_template" "$temp_file"
            ${atticTokenSubstitutions}
            ${pkgs.coreutils}/bin/chmod 600 "$temp_file"
            ${pkgs.coreutils}/bin/mv "$temp_file" "$config_file"
            trap - EXIT
          fi
        ''
      );
      imports = [
        (inputs.unified-pve.outPath + "/users/root")
        (inputs.unified-pve.outPath + "/modules/home-manager")
        (inputs.unified-pve.outPath + "/profiles/home-manager/proxmox-root.nix")
      ];
    };
}
