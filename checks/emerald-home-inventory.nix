# WHY: the two flakes pin different nixpkgs revisions, so compare logical
# names without retaining store-path dependencies in the resulting inventory.
home:
let
  names =
    values:
    builtins.sort builtins.lessThan (
      builtins.attrNames (
        builtins.listToAttrs (
          map (value: {
            name = builtins.unsafeDiscardStringContext value;
            value = null;
          }) values
        )
      )
    );
  renamedPrograms = [
    "exa" # programs.eza
    "gemini-cli" # programs.antigravity-cli
    "wpaperd" # services.wpaperd
  ];
in
{
  packages = names (map (pkg: pkg.pname or (builtins.parseDrvName pkg.name).name) home.home.packages);
  files = names (
    map (file: file.target) (builtins.filter (file: file.enable) (builtins.attrValues home.home.file))
  );
  # WHY: removed Home Manager options remain visible and throw on access.
  # Normalize unavailable options and disabled programs to the same state.
  programs = builtins.filter (
    name:
    let
      enabled = builtins.tryEval (home.programs.${name}.enable or false);
    in
    enabled.success && enabled.value == true
  ) (builtins.filter (name: !builtins.elem name renamedPrograms) (builtins.attrNames home.programs));
}
